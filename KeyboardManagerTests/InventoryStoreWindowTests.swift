import AppKit
import XCTest
@testable import KeyboardManager

@MainActor
final class InventoryStoreWindowTests: XCTestCase {
    func testCollectionStartsInKeyboardGallery() {
        let store = makeStore()

        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.selectedKind, .board)
    }

    func testSortPreferencesRoundTripPerKindAndIsolateInvalidEntries() throws {
        let domain = "SortPreferencesTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let sorts: [InventoryItemKind: InventorySort] = [
            .board: InventorySort(.manufacturer, order: .reverse),
            .keycapSet: InventorySort(.contents),
            .artisanSet: InventorySort(.photoCount, order: .reverse),
            .switchSet: InventorySort(.availableQuantity, order: .reverse)
        ]
        let store = InventoryStore(preferences: preferences)
        for (kind, sort) in sorts {
            store.selectedKind = kind
            XCTAssertEqual(store.collectionSort, .name)
            store.collectionSort = sort
        }
        let reopened = InventoryStore(preferences: preferences)
        XCTAssertEqual(reopened.overviewSortsByKind, sorts)
        XCTAssertEqual(reopened.route, .gallery)
        XCTAssertEqual(reopened.selectedKind, .board)

        preferences.set(["field": "removedColumn", "ascending": false], forKey: "collectionSort.artisanSet")
        preferences.set(["field": "quantity", "ascending": true], forKey: "collectionSort.keycapSet")
        let recovered = InventoryStore(preferences: preferences)
        for (kind, sort) in sorts {
            recovered.selectedKind = kind
            XCTAssertEqual(recovered.collectionSort, kind == .artisanSet || kind == .keycapSet ? .name : sort)
        }
    }

    func testLeavingCleanEditorReturnsToKeyboardGallery() {
        let store = makeStore()
        store.prepareNewItem(.keycapSet)

        store.leaveEditor()

        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.selectedKind, .board)
        XCTAssertFalse(store.isDiscardConfirmationPresented)
    }

    func testLeavingDirtyEditorReturnsToKeyboardGalleryOnlyAfterDiscard() {
        let store = makeStore()
        store.prepareNewItem(.artisanSet)
        store.isEditorDirty = true
        let editor = store.editorIdentity

        store.leaveEditor()
        XCTAssertTrue(store.isDiscardConfirmationPresented)
        store.cancelDiscard()
        XCTAssertTrue(store.isEditorDirty)
        XCTAssertEqual(store.route, .capture)
        XCTAssertEqual(store.editorIdentity, editor)

        store.leaveEditor()
        store.confirmDiscardAndContinue()

        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.selectedKind, .board)
        XCTAssertFalse(store.isEditorDirty)
    }

    func testSavingNewNonKeyboardItemReturnsToKeyboardGallery() async {
        let store = makeStore()
        await store.load()
        store.prepareNewItem(.keycapSet)
        var draft = store.editorDraft()
        draft.name = "Workshop Caps"

        let succeeded = await store.save(draft, preparedPhotos: [])

        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.snapshot.keycapSets.map(\.name), ["Workshop Caps"])
        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.selectedKind, .board)
    }

    func testPreferredLanguageIsNormalizedAndPersistedInSnapshot() async throws {
        let repository = InMemoryInventoryRepository()
        let store = InventoryStore(repository: repository)

        await store.load()
        await store.updatePreferredLanguage("en")

        XCTAssertEqual(store.snapshot.metadata.preferredLanguage, "en")
        let persisted = try await repository.loadSnapshot()
        XCTAssertEqual(persisted.metadata.preferredLanguage, "en")
        XCTAssertNil(store.languagePersistenceError)

        await store.updatePreferredLanguage("unsupported")
        XCTAssertEqual(store.snapshot.metadata.preferredLanguage, "de")
    }

    func testConfirmedNewDraftOfSameKindGetsFreshEditorIdentity() {
        let store = makeStore()
        store.prepareNewItem(.keycapSet)
        let firstIdentity = store.editorIdentity
        store.isEditorDirty = true
        store.prepareNewItem(.keycapSet)
        XCTAssertEqual(store.editorIdentity, firstIdentity)
        store.confirmDiscardAndContinue()
        XCTAssertNotEqual(store.editorIdentity, firstIdentity)
        XCTAssertFalse(store.isEditorDirty)
    }

    func testSavingEditorKeepsItsRouteAndWindow() {
        let store = makeStore()
        store.prepareNewItem(.board)
        let firstIdentity = store.editorIdentity
        store.editorSaveState = .saving
        store.prepareNewItem(.artisanSet)
        store.requestRoute(.gallery)
        store.editItem(kind: .switchSet, id: "other")
        XCTAssertEqual(store.route, .capture)
        XCTAssertEqual(store.editorIdentity, firstIdentity)
        XCTAssertFalse(store.shouldAllowWindowClose())
    }

    func testCleanEditorAllowsWindowToCloseImmediately() {
        let store = makeStore()
        store.prepareNewItem(.board)

        XCTAssertTrue(store.shouldAllowWindowClose())
        XCTAssertFalse(store.isWindowCloseConfirmationPresented)
        XCTAssertEqual(store.windowCloseRevision, 0)
    }

    func testDirtyEditorDefersCloseUntilUserConfirmsDiscard() {
        let store = makeStore()
        store.prepareNewItem(.board)
        store.isEditorDirty = true

        XCTAssertFalse(store.shouldAllowWindowClose())
        XCTAssertTrue(store.isWindowCloseConfirmationPresented)
        XCTAssertEqual(store.windowCloseRevision, 0)

        store.confirmDiscardAndCloseWindow()

        XCTAssertFalse(store.isEditorDirty)
        XCTAssertFalse(store.isWindowCloseConfirmationPresented)
        XCTAssertEqual(store.windowCloseRevision, 1)
    }

    func testCancellingWindowCloseKeepsDirtyDraft() {
        let store = makeStore()
        store.prepareNewItem(.switchSet)
        store.isEditorDirty = true

        XCTAssertFalse(store.shouldAllowWindowClose())
        store.cancelWindowClose()

        XCTAssertTrue(store.isEditorDirty)
        XCTAssertFalse(store.isWindowCloseConfirmationPresented)
        XCTAssertEqual(store.windowCloseRevision, 0)
    }

    func testCaptureRouteAlwaysStartsBlankDraftAfterEditingExistingItem() {
        let store = makeStore()
        store.snapshot = InventorySnapshot(
            metadata: .empty,
            libraryValues: .empty,
            boards: [Board(id: "board-1", name: "Board")],
            keycapSets: [KeycapSet(id: "keycap-1", name: "Keycaps")],
            artisanSets: [ArtisanSet(id: "artisan-1", name: "Artisan")],
            switchSets: [SwitchSet(id: "switch-1", name: "Switches")],
            switchInstallations: [],
            photos: []
        )

        let existingItems: [(InventoryItemKind, String)] = [
            (.board, "board-1"),
            (.keycapSet, "keycap-1"),
            (.artisanSet, "artisan-1"),
            (.switchSet, "switch-1")
        ]

        for (kind, id) in existingItems {
            store.editItem(kind: kind, id: id)
            XCTAssertEqual(store.editorDraft().normalizedName.isEmpty, false)

            store.requestRoute(.overview)
            store.requestRoute(.capture)

            XCTAssertEqual(store.route, .capture)
            XCTAssertEqual(store.selectedKind, kind)
            XCTAssertNil(store.selectedItemID)
            XCTAssertEqual(store.editorDraft().kind, kind)
            XCTAssertTrue(store.editorDraft().normalizedName.isEmpty)
        }
    }

    func testSavingEditedItemReturnsToGalleryAndPreservesOverviewSession() async throws {
        let snapshot = InventorySnapshot(
            metadata: .empty,
            libraryValues: .empty,
            boards: [Board(id: "board-1", name: "Before")],
            keycapSets: [],
            artisanSets: [],
            switchSets: [],
            switchInstallations: [],
            photos: []
        )
        let store = InventoryStore(
            repository: InMemoryInventoryRepository(snapshot: snapshot)
        )
        await store.load()

        var filters = InventoryFilters()
        filters.manufacturer = "Mode"
        store.overviewFiltersByKind[.board] = filters
        store.collectionSort = .recentlyUpdated
        store.updateOverviewScrollOffset(243.5, for: .board)
        store.editItem(kind: .board, id: "board-1")

        var draft = store.editorDraft()
        draft.name = "After"
        let succeeded = await store.save(draft, preparedPhotos: [])

        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.selectedKind, .board)
        XCTAssertEqual(store.overviewSelectionByKind[.board], "board-1")
        XCTAssertEqual(
            store.overviewFiltersByKind[.board]?.manufacturer,
            "Mode"
        )
        XCTAssertEqual(store.overviewSortsByKind[.board], .recentlyUpdated)
        let restoredOffset = try XCTUnwrap(
            store.overviewRestoreRequest?.scrollOffset
        )
        XCTAssertEqual(restoredOffset, 243.5, accuracy: 0.001)
        XCTAssertEqual(store.overviewRestoreRequest?.itemID, "board-1")
        XCTAssertEqual(store.overviewRestoreRequest?.kind, .board)
        XCTAssertEqual(store.overviewRestoreRequest?.revision, 1)
    }

    func testDiscardingEditedItemBackToOverviewRequestsSameRestoration() async {
        let snapshot = InventorySnapshot(
            metadata: .empty,
            libraryValues: .empty,
            boards: [Board(id: "board-1", name: "Board")],
            keycapSets: [],
            artisanSets: [],
            switchSets: [],
            switchInstallations: [],
            photos: []
        )
        let store = InventoryStore(
            repository: InMemoryInventoryRepository(snapshot: snapshot)
        )
        await store.load()
        store.updateOverviewScrollOffset(96, for: .board)
        store.editItem(kind: .board, id: "board-1")
        store.isEditorDirty = true

        store.requestRoute(.overview)

        XCTAssertEqual(store.route, .capture)
        XCTAssertTrue(store.isDiscardConfirmationPresented)

        store.confirmDiscardAndContinue()

        XCTAssertEqual(store.route, .overview)
        XCTAssertFalse(store.isDiscardConfirmationPresented)
        XCTAssertEqual(store.overviewRestoreRequest?.itemID, "board-1")
        XCTAssertEqual(store.overviewRestoreRequest?.scrollOffset, 96)
    }

    func testTableBridgeRestoresPixelOffsetAndKeyboardFocus() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: window.contentLayoutRect)
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 200)
        )
        scrollView.hasVerticalScroller = true

        let tableView = NSTableView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 900)
        )
        for index in 0..<5 {
            tableView.addTableColumn(
                NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            )
        }
        let dataSource = TableBridgeDataSource(rowCount: 30)
        tableView.dataSource = dataSource
        tableView.reloadData()
        tableView.frame.size.height = 900
        scrollView.documentView = tableView

        let locator = TableLocatorView(frame: .zero)
        rootView.addSubview(scrollView)
        rootView.addSubview(locator)
        window.contentView = rootView

        let coordinator = OverviewTableFocusBridge.Coordinator(
            onScrollOffsetChange: { _ in },
            onRestoreApplied: { _ in }
        )
        coordinator.update(
            restoreRequest: OverviewRestoreRequest(
                revision: 1,
                kind: .board,
                itemID: "board-1",
                scrollOffset: 180
            ),
            selectedRow: 8,
            rowCount: 30,
            onScrollOffsetChange: { _ in },
            onRestoreApplied: { _ in }
        )
        coordinator.resolveTable(from: locator)

        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            180,
            accuracy: 0.001
        )
        XCTAssertTrue(window.firstResponder === tableView)
        coordinator.detach()
    }

    private func makeStore() -> InventoryStore {
        InventoryStore(repository: InMemoryInventoryRepository())
    }
}

private final class TableBridgeDataSource: NSObject, NSTableViewDataSource {
    let rowCount: Int

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }
}
