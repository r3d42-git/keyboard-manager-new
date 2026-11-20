import Foundation
import Observation

@MainActor
@Observable
final class InventoryStore {
    var snapshot: InventorySnapshot = .empty
    var route: AppRoute = .gallery
    var selectedKind: InventoryItemKind = .board
    var selectedItemID: String?
    var overviewFiltersByKind: [InventoryItemKind: InventoryFilters] = [:]
    private(set) var overviewSortsByKind: [InventoryItemKind: InventorySort] = [:]
    var collectionSort: InventorySort {
        get { overviewSortsByKind[selectedKind, default: .name] }
        set {
            guard newValue != collectionSort,
                  InventorySort.Field.available(for: selectedKind).contains(newValue.field) else { return }
            overviewSortsByKind[selectedKind] = newValue
            if let preferences { newValue.save(for: selectedKind, in: preferences) }
        }
    }
    private(set) var overviewSelectionByKind: [InventoryItemKind: String] = [:]
    private(set) var overviewScrollOffsetByKind: [InventoryItemKind: Double] = [:]
    private(set) var overviewRestoreRequest: OverviewRestoreRequest?
    var loadState: LoadState = .idle
    var editorSaveState: EditorSaveState = .idle
    var isEditorDirty = false
    var isDiscardConfirmationPresented = false
    var isWindowCloseConfirmationPresented = false
    var navigationRevision = 0
    private(set) var windowCloseRevision = 0
    var backupExportState: BackupExportState = .idle
    var isBackupRestorePresented = false
    private(set) var backupRestoreState: BackupRestoreState = .idle
    private(set) var backupRestoreRevision = 0
    var isReportExportPresented = false
    var reportExportState: InventoryReportExportState = .idle
    private(set) var languagePersistenceError: String?

    private let repository: any InventoryRepository
    private let preferences: UserDefaults?
    private let backupExportService: BackupExportService
    private let backupRestoreService: BackupRestoreService
    private let reportExportService: InventoryReportExportService
    private let editingService = InventoryEditingService()
    private let photoService: PhotoImportService
    private let thumbnailService: ThumbnailService
    private var pendingEditorNavigation: EditorNavigationTarget?
    private var pendingOverviewReturn: OverviewReturnContext?
    private var overviewRestoreRevision = 0
    private var editorRevision = 0
    private var isSavingPreferredLanguage = false
    private var activeEditorPhotoPreparations = 0
    private var activeThumbnailRequests = 0
    private var thumbnailDrain: CheckedContinuation<Void, Never>?
    private var backupRestoreSession: UUID?
    private var backupPreparationTask: Task<BackupRestorePreview, Error>?
    private var isCancellingBackupRestore = false

    init(
        repository: any InventoryRepository = SQLiteInventoryRepository(),
        backupExportService: BackupExportService = BackupExportService(),
        backupRestoreService: BackupRestoreService = BackupRestoreService(),
        reportExportService: InventoryReportExportService = InventoryReportExportService(),
        photoService: PhotoImportService = PhotoImportService(),
        thumbnailService: ThumbnailService = ThumbnailService(),
        preferences: UserDefaults? = nil
    ) {
        self.repository = repository
        self.backupExportService = backupExportService
        self.backupRestoreService = backupRestoreService
        self.reportExportService = reportExportService
        self.photoService = photoService
        self.thumbnailService = thumbnailService
        self.preferences = preferences
        if let preferences {
            for kind in InventoryItemKind.allCases {
                overviewSortsByKind[kind] = InventorySort.saved(for: kind, in: preferences)
            }
        }
    }

    func load() async {
        guard loadState == .idle, !isBackupRestoreActive else { return }
        loadState = .loading

        do {
            snapshot = try await repository.loadSnapshot()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updatePreferredLanguage(_ value: String) async {
        let normalized = AppLanguage.normalized(value).rawValue
        guard loadState == .loaded, !isBackupRestoreActive,
              editorSaveState != .saving, !isSavingPreferredLanguage else { return }
        guard snapshot.metadata.preferredLanguage != normalized else {
            languagePersistenceError = nil
            return
        }
        isSavingPreferredLanguage = true
        defer { isSavingPreferredLanguage = false }
        var updated = snapshot
        updated.metadata.preferredLanguage = normalized
        do {
            try await repository.saveSnapshot(updated)
            snapshot = updated
            languagePersistenceError = nil
        } catch {
            languagePersistenceError = L10n.text(
                "Die Sprachauswahl konnte nicht gespeichert werden: %@",
                arguments: error.localizedDescription
            )
        }
    }

    var canStartEditor: Bool {
        loadState == .loaded && canNavigateEditor
    }

    private var canNavigateEditor: Bool {
        !isBackupRestoreActive && editorSaveState != .saving && activeEditorPhotoPreparations == 0
    }

    func prepareNewItem(_ kind: InventoryItemKind) {
        guard canNavigateEditor else { return }
        guard !needsDiscardConfirmation else {
            pendingEditorNavigation = .new(kind)
            isDiscardConfirmationPresented = true
            return
        }
        openNewItem(kind)
    }

    func requestRoute(_ newRoute: AppRoute) {
        guard canNavigateEditor else { return }
        guard newRoute != route else { return }
        guard !needsDiscardConfirmation else {
            pendingEditorNavigation = .route(newRoute)
            isDiscardConfirmationPresented = true
            navigationRevision += 1
            return
        }
        if newRoute == .capture {
            openNewItem(selectedKind)
            return
        }
        if newRoute == .overview, let pendingOverviewReturn {
            scheduleOverviewRestore(
                kind: pendingOverviewReturn.kind,
                itemID: pendingOverviewReturn.itemID
            )
        }
        if newRoute == .gallery, !InventoryQuery.galleryKinds.contains(selectedKind) {
            selectKeyboardGallery()
            return
        }
        route = newRoute
    }

    func leaveEditor() {
        guard route == .capture, canNavigateEditor else { return }
        if needsDiscardConfirmation {
            pendingEditorNavigation = .leaveEditor
            isDiscardConfirmationPresented = true
            return
        }
        if let pendingOverviewReturn {
            scheduleOverviewRestore(kind: pendingOverviewReturn.kind, itemID: pendingOverviewReturn.itemID)
        }
        selectKeyboardGallery()
    }

    func editItem(kind: InventoryItemKind, id: String) {
        guard canNavigateEditor else { return }
        guard !needsDiscardConfirmation else {
            pendingEditorNavigation = .edit(kind, id)
            isDiscardConfirmationPresented = true
            return
        }
        openEditor(kind: kind, id: id)
    }

    func updateOverviewSelection(_ id: String?, for kind: InventoryItemKind) {
        if let id {
            overviewSelectionByKind[kind] = id
        } else {
            overviewSelectionByKind.removeValue(forKey: kind)
        }
        if selectedKind == kind {
            selectedItemID = id
        }
    }

    func updateOverviewScrollOffset(_ offset: Double, for kind: InventoryItemKind) {
        guard offset.isFinite else { return }
        overviewScrollOffsetByKind[kind] = max(0, offset)
    }

    func consumeOverviewRestoreRequest(revision: Int) {
        guard overviewRestoreRequest?.revision == revision else { return }
        overviewRestoreRequest = nil
    }

    func confirmDiscardAndContinue() {
        let target = pendingEditorNavigation
        pendingEditorNavigation = nil
        isDiscardConfirmationPresented = false
        guard canNavigateEditor else { return }
        if case .restoreBackup = target {
            guard canRestoreBackup else { return }
        }
        isEditorDirty = false
        switch target {
        case let .route(route):
            requestRoute(route)
        case .leaveEditor:
            leaveEditor()
        case let .new(kind):
            openNewItem(kind)
        case let .edit(kind, id):
            openEditor(kind: kind, id: id)
        case .restoreBackup:
            if let pendingOverviewReturn {
                scheduleOverviewRestore(kind: pendingOverviewReturn.kind, itemID: pendingOverviewReturn.itemID)
            }
            route = .overview
            openBackupRestore()
        case nil:
            break
        }
    }

    func cancelDiscard() {
        pendingEditorNavigation = nil
        isDiscardConfirmationPresented = false
        navigationRevision += 1
    }

    func shouldAllowWindowClose() -> Bool {
        guard canNavigateEditor else { return false }
        guard needsDiscardConfirmation else { return true }
        isWindowCloseConfirmationPresented = true
        return false
    }

    func confirmDiscardAndCloseWindow() {
        isWindowCloseConfirmationPresented = false
        guard canNavigateEditor else { return }
        isEditorDirty = false
        windowCloseRevision += 1
    }

    func cancelWindowClose() {
        isWindowCloseConfirmationPresented = false
    }

    func editorDraft() -> InventoryDraft {
        guard let selectedItemID else {
            return InventoryDraft(kind: selectedKind)
        }
        switch selectedKind {
        case .board:
            return snapshot.boards.first(where: { $0.id == selectedItemID })
                .map { InventoryDraft(board: $0, installations: snapshot.switchInstallations) }
                ?? InventoryDraft(kind: .board)
        case .keycapSet:
            return snapshot.keycapSets.first(where: { $0.id == selectedItemID })
                .map(InventoryDraft.init(keycapSet:))
                ?? InventoryDraft(kind: .keycapSet)
        case .artisanSet:
            return snapshot.artisanSets.first(where: { $0.id == selectedItemID })
                .map(InventoryDraft.init(artisanSet:))
                ?? InventoryDraft(kind: .artisanSet)
        case .switchSet:
            return snapshot.switchSets.first(where: { $0.id == selectedItemID })
                .map { InventoryDraft(switchSet: $0, installations: snapshot.switchInstallations) }
                ?? InventoryDraft(kind: .switchSet)
        }
    }

    var editorIdentity: String {
        "\(editorRevision)::\(selectedKind.rawValue)::\(selectedItemID ?? "new")"
    }

    func preparePhotos(urls: [URL], for draft: InventoryDraft) async throws -> [PreparedPhoto] {
        try await prepareEditorPhotos(for: draft) { owner in
            try await photoService.prepare(urls: urls, owner: owner)
        }
    }

    func prepareExternalPhotos(urlStrings: [String], for draft: InventoryDraft) async throws -> [PreparedPhoto] {
        try await prepareEditorPhotos(for: draft) { owner in
            try await photoService.prepareExternal(urlStrings: urlStrings, owner: owner)
        }
    }

    private func prepareEditorPhotos(
        for draft: InventoryDraft,
        using prepare: (PhotoOwner) async throws -> [PreparedPhoto]
    ) async throws -> [PreparedPhoto] {
        guard !isBackupRestoreActive, editorSaveState != .saving,
              !isDiscardConfirmationPresented, !isWindowCloseConfirmationPresented else {
            throw CancellationError()
        }
        activeEditorPhotoPreparations += 1
        defer { activeEditorPhotoPreparations -= 1 }
        let owner = PhotoOwner(type: photoOwnerType(for: draft.kind), id: draft.id)
        return try await prepare(owner)
    }

    func photoRecord(id: String?) -> PhotoRecord? {
        guard let id else { return nil }
        return snapshot.photos.first { $0.id == id }
    }

    func thumbnailData(for record: PhotoRecord) async -> Data? {
        guard !isBackupRestoreInstalling else { return nil }
        activeThumbnailRequests += 1
        defer {
            activeThumbnailRequests -= 1
            if activeThumbnailRequests == 0 {
                thumbnailDrain?.resume()
                thumbnailDrain = nil
            }
        }
        let data = await thumbnailService.thumbnailData(for: record)
        return isBackupRestoreInstalling ? nil : data
    }

    func photoData(for record: PhotoRecord) async -> Data? {
        guard !isBackupRestoreInstalling else { return nil }
        let revision = backupRestoreRevision
        let data = await photoService.data(for: record)
        return isBackupRestoreInstalling || revision != backupRestoreRevision ? nil : data
    }

    func save(_ draft: InventoryDraft, preparedPhotos: [PreparedPhoto]) async -> Bool {
        guard canNavigateEditor, !isSavingPreferredLanguage else { return false }
        editorSaveState = .saving
        var draft = draft
        for photo in preparedPhotos where !draft.photoIDs.contains(photo.record.id) {
            draft.photoIDs.append(photo.record.id)
        }
        if draft.mainPhotoID == nil {
            draft.mainPhotoID = draft.photoIDs.first
        }

        do {
            let result = try editingService.saving(
                draft,
                newPhotos: preparedPhotos.map(\.record),
                in: snapshot
            )
            try await photoService.commit(preparedPhotos)
            do {
                try await repository.saveSnapshot(result.snapshot)
            } catch {
                await photoService.remove(preparedPhotos.map(\.record))
                throw error
            }
            await photoService.remove(result.removedPhotos)
            await thumbnailService.remove(result.removedPhotos)
            snapshot = result.snapshot
            isEditorDirty = false
            editorSaveState = .saved(
                L10n.text("„%@“ wurde gespeichert.", arguments: draft.normalizedName)
            )
            scheduleOverviewRestore(kind: draft.kind, itemID: draft.id)
            selectKeyboardGallery()
            return true
        } catch {
            editorSaveState = .failed(error.localizedDescription)
            return false
        }
    }

    func deleteItem(kind: InventoryItemKind, id: String) async -> Bool {
        guard canNavigateEditor, !isSavingPreferredLanguage else { return false }
        editorSaveState = .saving
        let wasEditing = route == .capture
        do {
            let result = try editingService.deleting(kind: kind, id: id, in: snapshot)
            try await repository.saveSnapshot(result.snapshot)
            await photoService.remove(result.removedPhotos)
            await thumbnailService.remove(result.removedPhotos)
            snapshot = result.snapshot
            if selectedItemID == id {
                selectedItemID = nil
            }
            isEditorDirty = false
            editorSaveState = .saved(L10n.text("Der Eintrag wurde gelöscht."))
            if wasEditing {
                scheduleOverviewRestore(kind: kind, itemID: nil)
                selectKeyboardGallery()
            } else {
                route = .overview
            }
            return true
        } catch {
            editorSaveState = .failed(error.localizedDescription)
            return false
        }
    }

    func clearEditorStatus() {
        guard editorSaveState != .saving else { return }
        editorSaveState = .idle
    }

    var canExportBackup: Bool {
        guard loadState == .loaded, !isBackupRestoreActive,
              editorSaveState != .saving else { return false }
        if case .exporting = backupExportState { return false }
        return true
    }

    func exportBackup(to destinationURL: URL) async {
        guard canExportBackup else { return }
        backupExportState = .exporting
        let hasSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let appVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.1.0"
            let result = try await backupExportService.export(
                snapshot: snapshot,
                to: destinationURL,
                appVersion: appVersion
            )
            backupExportState = .succeeded(result)
        } catch {
            backupExportState = .failed(error.localizedDescription)
        }
    }

    func clearBackupExportStatus() {
        if case .exporting = backupExportState {
            return
        }
        backupExportState = .idle
    }

    var isBackupRestoreActive: Bool {
        backupRestoreSession != nil || isCancellingBackupRestore
    }

    var isBackupRestoreInstalling: Bool {
        backupRestoreState == .installing
    }

    var canRestoreBackup: Bool {
        guard canNavigateEditor, !isSavingPreferredLanguage, !isReportExportPresented,
              !isDiscardConfirmationPresented, !isWindowCloseConfirmationPresented else { return false }
        if case .exporting = backupExportState { return false }
        if case .exporting = reportExportState { return false }
        switch loadState {
        case .loaded, .failed: return true
        case .idle, .loading: return false
        }
    }

    func requestBackupRestore() {
        guard canRestoreBackup else { return }
        if needsDiscardConfirmation {
            pendingEditorNavigation = .restoreBackup
            isDiscardConfirmationPresented = true
            return
        }
        openBackupRestore()
    }

    func prepareBackupRestore(from source: URL) async {
        guard let session = backupRestoreSession, !isCancellingBackupRestore else { return }
        switch backupRestoreState {
        case .idle, .failed, .ready: break
        case .preparing, .installing, .succeeded: return
        }
        backupRestoreState = .preparing
        let language = loadState == .loaded ? snapshot.metadata.preferredLanguage : AppLanguage.current.rawValue
        let service = backupRestoreService
        let task = Task {
            try await service.discardPrepared()
            return try await service.prepare(from: source, preferredLanguage: language)
        }
        backupPreparationTask = task

        do {
            let preview = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard backupRestoreSession == session else { return }
            if Task.isCancelled {
                try await service.discardPrepared()
                guard backupRestoreSession == session else { return }
                backupRestoreState = .idle
            } else {
                backupRestoreState = .ready(preview)
            }
        } catch {
            guard backupRestoreSession == session else { return }
            backupRestoreState = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
        backupPreparationTask = nil
    }

    func cancelBackupRestore() async {
        guard backupRestoreSession != nil, !isBackupRestoreInstalling, !isCancellingBackupRestore else { return }
        isCancellingBackupRestore = true
        backupRestoreSession = nil
        defer { isCancellingBackupRestore = false }

        let task = backupPreparationTask
        backupPreparationTask = nil
        task?.cancel()
        _ = await task?.result
        do {
            try await backupRestoreService.discardPrepared()
            backupRestoreState = .idle
            isBackupRestorePresented = false
        } catch {
            backupRestoreSession = UUID()
            backupRestoreState = .failed(error.localizedDescription)
        }
    }

    func installBackupRestore() async {
        guard backupRestoreSession != nil, case .ready = backupRestoreState else { return }
        backupRestoreState = .installing
        if activeThumbnailRequests > 0 {
            await withCheckedContinuation { continuation in
                thumbnailDrain = continuation
            }
        }
        do {
            let installation = try await backupRestoreService.install()
            await thumbnailService.clearMemoryCache()
            snapshot = installation.snapshot
            loadState = .loaded
            let counts = installation.result.counts
            if counts.value(for: selectedKind) == 0 {
                selectedKind = InventoryItemKind.allCases.first { counts.value(for: $0) > 0 } ?? .board
            }
            selectedItemID = nil
            overviewFiltersByKind.removeAll()
            overviewSelectionByKind.removeAll()
            overviewScrollOffsetByKind.removeAll()
            overviewRestoreRequest = nil
            pendingOverviewReturn = nil
            editorSaveState = .idle
            backupExportState = .idle
            reportExportState = .idle
            isEditorDirty = false
            languagePersistenceError = nil
            editorRevision += 1
            route = .overview
            backupRestoreRevision += 1
            backupRestoreState = .succeeded(installation.result)
        } catch {
            backupRestoreState = .failed(error.localizedDescription)
        }
    }

    var canExportReport: Bool {
        guard loadState == .loaded, !isBackupRestoreActive,
              editorSaveState != .saving else { return false }
        if case .exporting = reportExportState { return false }
        return true
    }

    func exportReport(
        context: InventoryReportContext,
        options: InventoryReportOptions,
        to destinationURL: URL
    ) async {
        guard canExportReport else { return }
        reportExportState = .exporting(options.format)
        let hasSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let appVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.1.0"
            let report = try InventoryReportBuilder.build(
                snapshot: snapshot,
                context: context,
                options: options,
                appVersion: appVersion
            )
            let result = try await reportExportService.export(
                report: report,
                format: options.format,
                to: destinationURL
            )
            reportExportState = .succeeded(result)
        } catch {
            reportExportState = .failed(error.localizedDescription)
        }
    }

    func clearReportExportStatus() {
        if case .exporting = reportExportState {
            return
        }
        reportExportState = .idle
    }

    func libraryValues(for key: String) -> [String] {
        snapshot.libraryValues.valuesByKey[key, default: []]
    }

    private var needsDiscardConfirmation: Bool {
        route == .capture && isEditorDirty
    }

    private func selectKeyboardGallery() {
        selectedKind = .board
        selectedItemID = overviewSelectionByKind[.board]
        route = .gallery
    }

    private func openBackupRestore() {
        backupRestoreSession = UUID()
        backupRestoreState = .idle
        isBackupRestorePresented = true
    }

    private func openNewItem(_ kind: InventoryItemKind) {
        editorRevision += 1
        pendingOverviewReturn = nil
        selectedKind = kind
        selectedItemID = nil
        editorSaveState = .idle
        isEditorDirty = false
        route = .capture
    }

    private func openEditor(kind: InventoryItemKind, id: String) {
        editorRevision += 1
        updateOverviewSelection(id, for: kind)
        pendingOverviewReturn = OverviewReturnContext(
            kind: kind,
            itemID: id,
            scrollOffset: overviewScrollOffsetByKind[kind]
        )
        selectedKind = kind
        selectedItemID = id
        editorSaveState = .idle
        isEditorDirty = false
        route = .capture
    }

    private func scheduleOverviewRestore(kind: InventoryItemKind, itemID: String?) {
        let scrollOffset: Double?
        if pendingOverviewReturn?.kind == kind {
            scrollOffset = pendingOverviewReturn?.scrollOffset
        } else {
            scrollOffset = nil
        }
        overviewRestoreRevision += 1
        overviewRestoreRequest = OverviewRestoreRequest(
            revision: overviewRestoreRevision,
            kind: kind,
            itemID: itemID,
            scrollOffset: scrollOffset
        )
        selectedKind = kind
        updateOverviewSelection(itemID, for: kind)
        pendingOverviewReturn = nil
    }

    private func photoOwnerType(for kind: InventoryItemKind) -> PhotoOwnerType {
        switch kind {
        case .board: .board
        case .keycapSet: .keycapSet
        case .artisanSet: .artisanSet
        case .switchSet: .switchSet
        }
    }
}

struct OverviewRestoreRequest: Equatable, Sendable {
    var revision: Int
    var kind: InventoryItemKind
    var itemID: String?
    var scrollOffset: Double?
}

private struct OverviewReturnContext {
    var kind: InventoryItemKind
    var itemID: String
    var scrollOffset: Double?
}

enum EditorSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved(String)
    case failed(String)
}

enum BackupExportState: Equatable, Sendable {
    case idle
    case exporting
    case succeeded(BackupExportResult)
    case failed(String)
}

private enum EditorNavigationTarget {
    case route(AppRoute)
    case leaveEditor
    case new(InventoryItemKind)
    case edit(InventoryItemKind, String)
    case restoreBackup
}
