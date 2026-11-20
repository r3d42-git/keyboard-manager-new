import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    private enum EditorSection: String, CaseIterable, Identifiable {
        case details, connections, photos, notes

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .details: "Daten"
            case .connections: "Verknüpfungen"
            case .photos: "Fotos"
            case .notes: "Notizen"
            }
        }
    }

    private enum PhotoSource {
        case local([URL])
        case external([String])
    }

    @Bindable var store: InventoryStore
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager
    @State private var photoUndoTarget = UndoBridge()
    @State private var draft = InventoryDraft(kind: .board)
    @State private var baseline = InventoryDraft(kind: .board)
    @State private var selectedSection: EditorSection = .details
    @State private var listEntriesText = ""
    @State private var quantityText = "0"
    @State private var isQuantityInputValid = true
    @State private var invalidInstallationInputs: [String: String] = [:]
    @State private var preparedPhotos: [PreparedPhoto] = []
    @State private var isPhotoImporterPresented = false
    @State private var photoImporterOwner: String?
    @State private var isExternalPhotoConfirmationPresented = false
    @State private var photoPreparationTask: Task<Void, Never>?
    @State private var photoPreparationMessage: LocalizedStringKey?
    @State private var isDeleteConfirmationPresented = false
    @State private var photoImportError: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
                .disabled(isSaving)
            Divider()
            editorForm
                .disabled(isSaving)
            editorFooter
        }
        .textFieldStyle(.roundedBorder)
        .task(id: store.editorIdentity) {
            loadDraft()
            await Task.yield()
            if !Task.isCancelled {
                isNameFocused = true
            }
        }
        .onChange(of: draft) {
            updateDirtiness()
        }
        .onChange(of: preparedPhotos) {
            updateDirtiness()
        }
        .onChange(of: locale) {
            if isQuantityInputValid {
                quantityText = draft.quantity.formatted(quantityFormat)
            }
        }
        .onDisappear {
            cancelPhotoPreparation()
            undoManager?.removeAllActions(withTarget: photoUndoTarget)
        }
        .onExitCommand(perform: leaveEditor)
        .fileImporter(
            isPresented: $isPhotoImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true,
            onCompletion: handlePhotoSelection
        )
        .alert("Fotoimport fehlgeschlagen", isPresented: photoErrorPresented) {
            Button("OK", role: .cancel) {
                photoImportError = nil
            }
        } message: {
            Text(photoImportError ?? "")
        }
        .confirmationDialog(
            L10n.text("Externe Importbilder lokal übernehmen?"),
            isPresented: $isExternalPhotoConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Herunterladen und lokal übernehmen")) {
                preparePhotos(from: .external(externalImageURLs))
            }
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        } message: {
            Text(verbatim: L10n.text(
                "Beim Bestätigen lädt Keyboard Manager die Bilder einmalig per HTTPS von %@ und prüft sie. Beim Speichern werden die Bilder lokal übernommen und die externen Bildadressen aus dem Eintrag entfernt.",
                arguments: externalImageHostSummary
            ))
        }
        .confirmationDialog(
            "Ungespeicherte Änderungen verwerfen?",
            isPresented: $store.isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen", role: .destructive) {
                store.confirmDiscardAndContinue()
            }
            Button("Weiter bearbeiten", role: .cancel) {
                store.cancelDiscard()
            }
        } message: {
            Text("Der aktuelle Entwurf wurde noch nicht gespeichert.")
        }
        .confirmationDialog(
            "\(draft.kind.singularName) wirklich löschen?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard !isBusy else { return }
                Task {
                    _ = await store.deleteItem(kind: draft.kind, id: draft.id)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Eintrag und seine verwalteten Fotos werden dauerhaft entfernt. Verknüpfungen werden konsistent gelöst.")
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    editorTitle.fixedSize()
                    Spacer(minLength: 8)
                    sectionPicker
                }

                VStack(alignment: .leading, spacing: 8) {
                    editorTitle
                    sectionPicker
                }
            }

            HStack(spacing: 16) {
                nameField
                inventoryKind.fixedSize()
            }
        }
        .modifier(EditorInsets())
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var nameField: some View {
        HStack(spacing: 8) {
            Text("Name")
                .accessibilityHidden(true)

            TextField("Name", text: $draft.name, prompt: Text(""))
                .focused($isNameFocused)
                .accessibilityIdentifier("capture.name")
                .accessibilityLabel("Name, Pflichtfeld")

            if draft.normalizedName.isEmpty {
                Text("Pflichtfeld")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Abschnitte", selection: $selectedSection) {
            ForEach(EditorSection.allCases) { section in
                Text(section.title)
                    .tag(section)
                    .accessibilityIdentifier("capture.section.\(section.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("capture.sections")
    }

    private var editorTitle: some View {
        Text(store.selectedItemID == nil ? "Neuer Eintrag" : "Eintrag bearbeiten")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var inventoryKind: some View {
        if store.selectedItemID == nil {
            Picker("Inventartyp", selection: kindSelection) {
                ForEach(InventoryItemKind.allCases) { kind in
                    Label(kind.singularName, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("capture.kind")
            .fixedSize(horizontal: true, vertical: false)
            .disabled(isBusy)
        } else {
            Label(draft.kind.singularName, systemImage: draft.kind.systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var editorFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if store.selectedItemID != nil {
                    Button("Löschen …", systemImage: "trash", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(isBusy)
                    .fixedSize()
                }

                saveStatus
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button("Abbrechen", role: .cancel, action: leaveEditor)
                        .accessibilityIdentifier("capture.discard")
                        .disabled(isBusy)

                    Button("Speichern", action: save)
                        .accessibilityIdentifier("capture.save")
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
                .fixedSize()
            }
            .modifier(EditorInsets())
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorForm: some View {
        ScrollView {
            Group {
                switch selectedSection {
                case .details:
                    Form {
                        identitySection
                        kindSpecificSections
                        migrationMetadataSection
                    }
                    .formStyle(.columns)
                case .connections:
                    Form {
                        relationshipSection
                    }
                    .formStyle(.columns)
                case .photos:
                    photoSection
                case .notes:
                    notesSection
                }
            }
            .modifier(EditorInsets())
            .padding(.vertical, 16)
        }
        .id(selectedSection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var identitySection: some View {
        if draft.kind != .switchSet {
            Section("Basisdaten") {
                LibraryTextField(
                    title: "Hersteller",
                    text: $draft.manufacturer,
                    values: store.libraryValues(for: manufacturerLibraryKey)
                )
                if draft.kind == .keycapSet || draft.kind == .artisanSet {
                    LibraryTextField(
                        title: "Profil",
                        text: $draft.profile,
                        values: store.libraryValues(for: draft.kind == .keycapSet ? "keycapProfiles" : "artisanProfiles")
                    )
                    LibraryTextField(
                        title: "Material",
                        text: $draft.material,
                        values: store.libraryValues(for: draft.kind == .keycapSet ? "keycapMaterials" : "artisanMaterials")
                    )
                    LibraryTextField(
                        title: "Status",
                        text: $draft.status,
                        values: store.libraryValues(for: draft.kind == .keycapSet ? "keycapStatuses" : "artisanStatuses")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var kindSpecificSections: some View {
        switch draft.kind {
        case .board:
            Section("Keyboard") {
                LibraryTextField(title: "Format", text: $draft.format, values: store.libraryValues(for: "formats"))
                LibraryTextField(title: "Plate", text: $draft.plate, values: store.libraryValues(for: "plates"))
                LibraryTextField(title: "PCB", text: $draft.pcb, values: store.libraryValues(for: "pcbs"))
                LibraryTextField(title: "Stabilisatoren", text: $draft.stabilizers, values: store.libraryValues(for: "stabs"))
            }
        case .keycapSet:
            Section("Set-Inhalt") {
                editorTextField("Kits, durch Komma getrennt", text: listEntriesBinding)
                sourceFields
            }
        case .artisanSet:
            Section("Artisan") {
                editorTextField("Tags, durch Komma getrennt", text: listEntriesBinding)
                sourceFields
            }
        case .switchSet:
            switchTechnicalSection
        }
    }

    private func editorTextField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(""))
                .labelsHidden()
        }
    }

    private var sourceFields: some View {
        Group {
            editorTextField("Shop", text: $draft.sourceShop)
            editorTextField("HTTPS-Quelladresse", text: $draft.sourceURL)
                .textContentType(.URL)
        }
    }

    private var switchTechnicalSection: some View {
        Group {
            Section("Switch") {
                LibraryTextField(title: "Typ", text: $draft.switchType, values: store.libraryValues(for: "switchTypes"))
                Picker("Pins", selection: $draft.pins) {
                    ForEach(SwitchPins.allCases) { pins in
                        Text(pins.displayName).tag(pins)
                    }
                }
                editorTextField("Gesamtbestand", text: quantityBinding)
                    .accessibilityIdentifier("capture.stock")
                Toggle("LED-Diffusor", isOn: $draft.hasLEDDiffuser)
                    .toggleStyle(.checkbox)
                Toggle("Werkseitig geschmiert", isOn: $draft.isFactoryLubed)
                    .toggleStyle(.checkbox)
            }

            Section("Materialien") {
                LibraryTextField(title: "Top Housing", text: $draft.topHousingMaterial, values: store.libraryValues(for: "switchTopHousingMaterials"))
                LibraryTextField(title: "Bottom Housing", text: $draft.bottomHousingMaterial, values: store.libraryValues(for: "switchBottomHousingMaterials"))
                LibraryTextField(title: "Stem", text: $draft.stemMaterial, values: store.libraryValues(for: "switchStemMaterials"))
                LibraryTextField(title: "Federlänge", text: $draft.springLength, values: store.libraryValues(for: "switchSpringLengths"))
                LibraryTextField(title: "Federtyp", text: $draft.springType, values: store.libraryValues(for: "switchSpringTypes"))
            }

            Section("Wege und Kräfte") {
                LibraryTextField(title: "Pre-Travel", text: $draft.preTravel, values: store.libraryValues(for: "switchPreTravels"))
                LibraryTextField(title: "Total Travel", text: $draft.totalTravel, values: store.libraryValues(for: "switchTotalTravels"))
                LibraryTextField(title: "Operating Force", text: $draft.operatingForce, values: store.libraryValues(for: "switchOperatingForces"))
                LibraryTextField(title: "Bottom-out Force", text: $draft.bottomOutForce, values: store.libraryValues(for: "switchBottomOutForces"))
            }
        }
    }

    @ViewBuilder
    private var relationshipSection: some View {
        switch draft.kind {
        case .board:
            VStack(alignment: .leading, spacing: 20) {
                boardKeycapAssignments
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verbaute Switches").font(.headline)
                    boardSwitchInstallations
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .keycapSet, .artisanSet:
            Section("Montage") {
                Picker("Board", selection: optionalSelection($draft.mountedBoardID)) {
                    Text("Nicht montiert").tag("")
                    ForEach(store.snapshot.boards.sorted(by: nameSort)) { board in
                        Text(board.name).tag(board.id)
                    }
                }
            }
        case .switchSet:
            Section("Installationen") {
                if store.snapshot.boards.isEmpty {
                    Text("Noch keine Boards vorhanden.")
                        .foregroundStyle(.secondary)
                } else {
                    switchBoardInstallations
                    let installed = installedSwitchCount
                    LabeledContent("Verbaut") {
                        Text(verbatim: installed?.formatted(quantityFormat) ?? "—")
                            .monospacedDigit()
                    }
                    LabeledContent("Verfügbar") {
                        Text(installed.map { max(0, max(0, draft.quantity) - $0) } ?? 0, format: .number)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let mainPhotoID = draft.mainPhotoID {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        localPhotos.frame(minWidth: 290, idealWidth: 300, maxWidth: .infinity)
                        mainPhotoPreview(mainPhotoID)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        localPhotos
                        mainPhotoPreview(mainPhotoID)
                    }
                }
            } else {
                localPhotos
            }

            if !externalImageURLs.isEmpty {
                Divider()
                externalPhotos
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localPhotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fotos")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Button {
                photoImporterOwner = store.editorIdentity
                isPhotoImporterPresented = true
            } label: {
                Label("Fotos hinzufügen …", systemImage: "photo.badge.plus")
            }
            .disabled(isBusy)

            if allPhotoIDs.isEmpty {
                Text("Noch keine lokalen Fotos.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], alignment: .leading, spacing: 12) {
                    ForEach(allPhotoIDs, id: \.self) { photoID in
                        PhotoEditorTile(
                            isMain: draft.mainPhotoID == photoID,
                            setMain: {
                                registerPhotoUndo()
                                draft.mainPhotoID = photoID
                            },
                            remove: {
                                registerPhotoUndo()
                                removePhoto(photoID)
                            }
                        ) {
                            editorPhoto(photoID, purpose: .thumbnail)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Text("JPEG, PNG, GIF, WebP und HEIC; maximal 30 MiB. Große Bilder werden auf höchstens 1920 × 1080 Pixel skaliert.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mainPhotoPreview(_ photoID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hauptfoto")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            editorPhoto(photoID, purpose: .full)
                .frame(idealWidth: 260, maxWidth: 260)
                .frame(height: 184)
                .background(.quaternary)
                .clipShape(.rect(cornerRadius: 5))
                .accessibilityLabel("Hauptfoto")
        }
    }

    private var externalPhotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Externe Importbilder")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledContent("Bildadressen") {
                Text(externalImageURLs.count, format: .number)
                    .monospacedDigit()
            }

            Text("Diese importierten Bildadressen werden nicht automatisch aufgerufen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isExternalPhotoConfirmationPresented = true
            } label: {
                Label("Herunterladen und lokal übernehmen", systemImage: "icloud.and.arrow.down")
            }
            .disabled(isBusy)
        }
    }

    private var notesSection: some View {
        TextEditor(text: $draft.notes)
            .font(.body)
            .frame(minHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor))
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("Notizen")
    }

    @ViewBuilder
    private var migrationMetadataSection: some View {
        if draft.kind == .switchSet, !draft.importWarnings.isEmpty {
            Section("Migrationshinweise") {
                ForEach(draft.importWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch store.editorSaveState {
        case .idle:
            if let photoPreparationMessage {
                progressStatus(photoPreparationMessage)
            } else if let quantityError {
                Label(quantityError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if store.isEditorDirty {
                Label("Ungespeicherte Änderungen", systemImage: "pencil")
                    .foregroundStyle(.secondary)
            }
        case .saving:
            progressStatus("Wird gespeichert …")
        case let .saved(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(4)
                .help(message)
        }
    }

    private func progressStatus(_ message: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message)
        }
    }

    private var kindSelection: Binding<InventoryItemKind> {
        Binding(
            get: { store.selectedKind },
            set: { kind in
                guard kind != store.selectedKind, !isBusy else { return }
                updateDirtiness()
                store.prepareNewItem(kind)
            }
        )
    }

    private var listEntriesBinding: Binding<String> {
        Binding(
            get: { listEntriesText },
            set: { text in
                listEntriesText = text
                draft.listEntries = text == baseline.listEntries.joined(separator: ", ")
                    ? baseline.listEntries
                    : text.components(separatedBy: ",")
            }
        )
    }

    private var quantityFormat: IntegerFormatStyle<Int> {
        .number.locale(locale)
    }

    private func wholeNumber(_ text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(input) { return value }
        guard let value = try? Int(input, format: quantityFormat, lenient: false),
              value.formatted(quantityFormat) == input else { return nil }
        return value
    }

    private var quantityBinding: Binding<String> {
        Binding(
            get: { quantityText },
            set: { text in
                quantityText = text
                let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = input.isEmpty ? 0 : wholeNumber(input) {
                    draft.quantity = value
                    isQuantityInputValid = true
                } else {
                    isQuantityInputValid = false
                }
                updateDirtiness()
            }
        )
    }

    private var quantityError: LocalizedStringKey? {
        if !invalidInstallationInputs.isEmpty { return "Für die verbaute Anzahl eine positive ganze Zahl eingeben." }
        if draft.kind == .switchSet {
            if !isQuantityInputValid { return "Gesamtbestand als ganze Zahl eingeben." }
            if draft.quantity < 0 { return "Der Gesamtbestand darf nicht negativ sein." }
            guard let count = installedSwitchCount else { return "Die Summe der Installationsmengen ist zu groß." }
            if count > draft.quantity { return "Verbaut (\(count)) darf den Gesamtbestand (\(draft.quantity)) nicht überschreiten." }
        } else if draft.kind == .board {
            let capacities = switchCapacities
            for switchSet in store.snapshot.switchSets {
                if let count = draft.installations[switchSet.id],
                   let capacity = capacities[switchSet.id], count > capacity {
                    return "Für „\(switchSet.name)“ sind auf diesem Board höchstens \(capacity) Switches verfügbar."
                }
            }
        }
        return nil
    }

    private var installedSwitchCount: Int? {
        try? InventoryEditingService.totalInstalled(draft.installations.values)
    }

    // Switches already mounted on other boards cannot be allocated to this draft.
    private var switchCapacities: [String: Int] {
        var capacities = Dictionary(uniqueKeysWithValues: store.snapshot.switchSets.map { ($0.id, $0.quantity) })
        for link in store.snapshot.switchInstallations where link.boardID != draft.id {
            if let capacity = capacities[link.switchSetID] {
                capacities[link.switchSetID] = max(0, capacity - link.quantity)
            }
        }
        return capacities
    }

    private var allPhotoIDs: [String] {
        draft.photoIDs
    }

    private var manufacturerLibraryKey: String {
        switch draft.kind {
        case .board: "manufacturers"
        case .keycapSet: "keycapManufacturers"
        case .artisanSet: "artisanManufacturers"
        case .switchSet: ""
        }
    }

    private var isSaving: Bool {
        if case .saving = store.editorSaveState { return true }
        return false
    }

    private var isBusy: Bool {
        isSaving || photoPreparationTask != nil
    }

    private var canSave: Bool {
        !isBusy && quantityError == nil && !draft.normalizedName.isEmpty
    }

    private var externalImageURLs: [String] {
        var seen = Set<String>()
        return ([draft.coverURL] + draft.externalImageURLs).filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }

    private var externalImageHostSummary: String {
        let hosts = externalImageURLs.compactMap {
            URLComponents(string: $0)?.host
        }
        let uniqueHosts = Array(Set(hosts)).sorted()
        if uniqueHosts.isEmpty {
            return L10n.text("den hinterlegten Bildservern")
        }
        if uniqueHosts.count <= 3 {
            return uniqueHosts.joined(separator: ", ")
        }
        let firstHosts = uniqueHosts.prefix(3).joined(separator: ", ")
        let remaining = uniqueHosts.count - 3
        if remaining == 1 {
            return L10n.text("%@ und einem weiteren Host", arguments: firstHosts)
        }
        return L10n.text("%@ und %lld weiteren Hosts", arguments: firstHosts, remaining)
    }

    private var photoErrorPresented: Binding<Bool> {
        Binding(
            get: { photoImportError != nil },
            set: { if !$0 { photoImportError = nil } }
        )
    }

    private func optionalSelection(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private var boardKeycapAssignments: some View {
        let sets = store.snapshot.keycapSets
        let setsByID = Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        let selectedIDs = Set(draft.keycapSetIDs)
        let available = sets.filter { !selectedIDs.contains($0.id) }.sorted(by: nameSort)
        let boardNames = Dictionary(uniqueKeysWithValues: store.snapshot.boards.map { ($0.id, $0.name) })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Keycap-Sets").font(.headline)
            if selectedIDs.isEmpty {
                Text("Keine Keycap-Sets zugeordnet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.keycapSetIDs.compactMap { setsByID[$0] }) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Keycap-Set entfernen", systemImage: "minus.circle") {
                        draft.keycapSetIDs.removeAll { $0 == item.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(item.name) entfernen")
                }
            }
            Menu("Keycap-Set hinzufügen …") {
                ForEach(available) { item in
                    let boardName = item.mountedBoardID.flatMap { boardNames[$0] }
                    Button(boardName.map { "\(item.name) · \($0)" } ?? item.name) {
                        draft.keycapSetIDs.append(item.id)
                    }
                }
            }
            .fixedSize()
            .accessibilityIdentifier("capture.addKeycap")
            .disabled(available.isEmpty)
        }
    }

    private func installationRows(
        values: [(id: String, name: String, total: Int?)],
        removeLabel: LocalizedStringKey
    ) -> some View {
        ForEach(values, id: \.id) { value in
            let controls = installationControls(value, removeLabel: removeLabel)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(value.name)
                        .fixedSize()
                    Spacer(minLength: 0)
                    controls
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(value.name)
                        .fixedSize(horizontal: false, vertical: true)
                    controls
                }
            }
        }
    }

    private func installationControls(
        _ installation: (id: String, name: String, total: Int?),
        removeLabel: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 8) {
            TextField("Verbaut", text: installationText(installation.id))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 68)
                .accessibilityLabel("Verbaute Anzahl für \(installation.name)")
                .accessibilityIdentifier("capture.quantity.\(installation.id)")
            if let total = installation.total {
                Text("von \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(removeLabel, systemImage: "minus.circle") {
                invalidInstallationInputs.removeValue(forKey: installation.id)
                draft.installations.removeValue(forKey: installation.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .accessibilityLabel("\(installation.name) entfernen")
        }
    }

    @ViewBuilder
    private var boardSwitchInstallations: some View {
        let capacities = switchCapacities
        let installed = store.snapshot.switchSets
            .filter { (draft.installations[$0.id] ?? 0) > 0 }
            .sorted(by: nameSort)
            .map { ($0.id, $0.name, capacities[$0.id]) }
        let available = store.snapshot.switchSets
            .filter { draft.installations[$0.id, default: 0] == 0 }
            .sorted(by: nameSort)

        if store.snapshot.switchSets.isEmpty {
            Text("Noch keine Switch-Sets vorhanden.")
                .foregroundStyle(.secondary)
        } else if installed.isEmpty {
            Text("Noch keine Switches zugeordnet.")
                .foregroundStyle(.secondary)
        } else {
            installationRows(
                values: installed,
                removeLabel: "Switch entfernen"
            )
        }

        Menu("Switch hinzufügen …") {
            ForEach(available) { switchSet in
                Button(switchSet.name) {
                    draft.installations[switchSet.id] = 1
                }
                .disabled(capacities[switchSet.id, default: 0] < 1)
            }
        }
        .fixedSize()
        .accessibilityIdentifier("capture.addSwitch")
        .disabled(available.isEmpty)
    }

    @ViewBuilder
    private var switchBoardInstallations: some View {
        let installed = store.snapshot.boards
            .filter { (draft.installations[$0.id] ?? 0) > 0 }
            .sorted(by: nameSort)
            .map { ($0.id, $0.name, Optional<Int>.none) }
        let available = store.snapshot.boards
            .filter { draft.installations[$0.id, default: 0] == 0 }
            .sorted(by: nameSort)

        if installed.isEmpty {
            Text("Noch auf keinem Board installiert.")
                .foregroundStyle(.secondary)
        } else {
            Text("Installierte Boards").font(.headline)
            installationRows(
                values: installed,
                removeLabel: "Board entfernen"
            )
        }

        Menu("Board hinzufügen …") {
            ForEach(available) { board in
                Button(board.name) {
                    draft.installations[board.id] = 1
                }
            }
        }
        .disabled(available.isEmpty)
    }

    private func installationText(_ id: String) -> Binding<String> {
        Binding(
            get: { invalidInstallationInputs[id] ?? String(draft.installations[id, default: 0]) },
            set: { text in
                if let value = wholeNumber(text), value > 0 {
                    draft.installations[id] = value
                    invalidInstallationInputs.removeValue(forKey: id)
                } else {
                    invalidInstallationInputs[id] = text
                }
                updateDirtiness()
            }
        )
    }

    private func loadDraft() {
        cancelPhotoPreparation()
        undoManager?.removeAllActions(withTarget: photoUndoTarget)
        let loaded = store.editorDraft()
        draft = loaded
        baseline = loaded
        selectedSection = .details
        listEntriesText = loaded.listEntries.joined(separator: ", ")
        quantityText = loaded.quantity.formatted(quantityFormat)
        isQuantityInputValid = true
        invalidInstallationInputs.removeAll()
        preparedPhotos = []
        photoImportError = nil
        photoImporterOwner = nil
        isPhotoImporterPresented = false
        isExternalPhotoConfirmationPresented = false
        isDeleteConfirmationPresented = false
        store.isEditorDirty = false
    }

    private func updateDirtiness() {
        guard store.route == .capture, !isSaving else { return }
        store.isEditorDirty = draft != baseline || !preparedPhotos.isEmpty || !isQuantityInputValid || !invalidInstallationInputs.isEmpty
        if case .failed = store.editorSaveState {
            store.clearEditorStatus()
        }
    }

    private func leaveEditor() {
        guard !isBusy else { return }
        updateDirtiness()
        store.leaveEditor()
    }

    private func save() {
        guard canSave else { return }
        let editorIdentity = store.editorIdentity
        let submittedDraft = draft
        let submittedPhotos = preparedPhotos
        Task {
            guard !isBusy, store.route == .capture, store.editorIdentity == editorIdentity else { return }
            _ = await store.save(submittedDraft, preparedPhotos: submittedPhotos)
        }
    }

    private func handlePhotoSelection(_ result: Result<[URL], Error>) {
        defer { photoImporterOwner = nil }
        guard photoImporterOwner == store.editorIdentity, store.route == .capture else { return }
        switch result {
        case let .success(urls):
            guard !urls.isEmpty else { return }
            preparePhotos(from: .local(urls))
        case let .failure(error):
            photoImportError = error.localizedDescription
        }
    }

    private func preparePhotos(from source: PhotoSource) {
        guard !isBusy else { return }
        let editorIdentity = store.editorIdentity
        let ownerDraft = draft
        store.clearEditorStatus()
        switch source {
        case .local: photoPreparationMessage = "Fotos werden vorbereitet …"
        case .external: photoPreparationMessage = "Importbilder werden geladen …"
        }

        photoPreparationTask = Task {
            defer {
                if !Task.isCancelled {
                    photoPreparationTask = nil
                    photoPreparationMessage = nil
                }
            }
            do {
                let photos: [PreparedPhoto]
                switch source {
                case let .local(urls):
                    photos = try await store.preparePhotos(urls: urls, for: ownerDraft)
                case let .external(urls):
                    photos = try await store.prepareExternalPhotos(urlStrings: urls, for: ownerDraft)
                }
                try Task.checkCancellation()
                guard store.route == .capture, store.editorIdentity == editorIdentity else { return }
                registerPhotoUndo()
                preparedPhotos.append(contentsOf: photos)
                draft.photoIDs.append(contentsOf: photos.map(\.record.id))
                if draft.mainPhotoID == nil {
                    draft.mainPhotoID = photos.first?.record.id
                }
                if case .external = source {
                    draft.coverURL = ""
                    draft.externalImageURLs = []
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.route == .capture, store.editorIdentity == editorIdentity else { return }
                photoImportError = error.localizedDescription
            }
        }
    }

    private func cancelPhotoPreparation() {
        photoPreparationTask?.cancel()
        photoPreparationTask = nil
        photoPreparationMessage = nil
    }

    private func removePhoto(_ id: String) {
        draft.photoIDs.removeAll { $0 == id }
        preparedPhotos.removeAll { $0.record.id == id }
        if draft.mainPhotoID == id {
            draft.mainPhotoID = draft.photoIDs.first
        }
    }

    @ViewBuilder
    private func editorPhoto(_ photoID: String, purpose: ManagedPhotoPurpose) -> some View {
        if let prepared = preparedPhotos.first(where: { $0.record.id == photoID }) {
            PreparedEditorPhoto(data: prepared.data)
                .id(photoID)
        } else {
            ManagedPhotoView(
                store: store,
                record: store.photoRecord(id: photoID),
                purpose: purpose,
                showsCompactPlaceholder: purpose == .thumbnail
            )
        }
    }

    private func registerPhotoUndo() {
        let editorIdentity = store.editorIdentity
        let oldPhotoIDs = draft.photoIDs
        let oldMainPhoto = draft.mainPhotoID
        let oldCoverURL = draft.coverURL
        let oldExternalURLs = draft.externalImageURLs
        let oldPhotos = preparedPhotos
        undoManager?.registerUndo(withTarget: photoUndoTarget) { _ in
            MainActor.assumeIsolated {
                guard store.route == .capture, store.editorIdentity == editorIdentity, !isSaving else { return }
                registerPhotoUndo()
                draft.photoIDs = oldPhotoIDs
                draft.mainPhotoID = oldMainPhoto
                draft.coverURL = oldCoverURL
                draft.externalImageURLs = oldExternalURLs
                preparedPhotos = oldPhotos
            }
        }
        undoManager?.setActionName(L10n.text("Editoränderung"))
    }

    private func nameSort<T: Identifiable>(_ lhs: T, _ rhs: T) -> Bool where T: NamedInventoryItem {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private struct EditorInsets: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
    }
}

private protocol NamedInventoryItem {
    var name: String { get }
}

extension Board: NamedInventoryItem {}
extension KeycapSet: NamedInventoryItem {}
extension SwitchSet: NamedInventoryItem {}

@MainActor
private final class UndoBridge: NSObject {}

private struct PreparedEditorPhoto: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            image = NSImage(data: data)
        }
    }
}

private struct PhotoEditorTile<Photo: View>: View {
    var isMain: Bool
    var setMain: () -> Void
    var remove: () -> Void
    @ViewBuilder var photo: () -> Photo

    var body: some View {
        VStack(spacing: 6) {
            photo()
            .frame(width: 92, height: 72)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 5))
            .overlay(alignment: .topTrailing) {
                if isMain {
                    Image(systemName: "star.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .padding(5)
                }
            }

            HStack(spacing: 10) {
                Button(isMain ? "Hauptfoto" : "Als Hauptfoto", systemImage: isMain ? "star.fill" : "star", action: setMain)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(isMain ? "Hauptfoto" : "Als Hauptfoto")
                    .disabled(isMain)

                Button("Foto entfernen", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Foto entfernen")
            }
        }
    }
}

private struct LibraryTextField: View {
    var title: LocalizedStringKey
    @Binding var text: String
    var values: [String]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: $text, prompt: Text(""))
                    .labelsHidden()

                if !values.isEmpty {
                    Menu {
                        ForEach(values, id: \.self) { value in
                            Button(value) {
                                text = value
                            }
                        }
                    } label: {
                        Label("Bibliothekswert auswählen", systemImage: "chevron.down")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Vorhandenen Wert auswählen; freie Eingabe bleibt möglich.")
                }
            }
        }
    }
}
