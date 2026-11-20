import AppKit
import SwiftUI

struct OverviewView: View {
    @Bindable var store: InventoryStore
    @State private var spotlightItemID: String?
    @State private var deletionTarget: InventoryItemSummary?

    var body: some View {
        let items = store.collectionResults
        let selectedItem = currentSelection.flatMap { id in items.first { $0.id == id } }
        VStack(spacing: 0) {
            InventoryFilterBar(store: store, kinds: InventoryItemKind.allCases, resultCount: items.count)
            if items.isEmpty {
                InventoryCollectionEmptyView(store: store)
            } else {
                inventoryTable(items)
            }
            statusBanner
        }
        .searchable(text: $store.collectionFilters.searchText, placement: .toolbar, prompt: "Bestand durchsuchen")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    itemActions(selectedItem)
                } label: {
                    Label("Weitere Aktionen", systemImage: "ellipsis.circle")
                }
                .disabled(selectedItem == nil)
                .accessibilityIdentifier("overview.actions")
                .help("Weitere Aktionen")
            }
        }
        .onAppear {
            if let id = store.selectedItemID, items.contains(where: { $0.id == id }) {
                store.updateOverviewSelection(id, for: store.selectedKind)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { spotlightItemID != nil },
                set: { if !$0 { spotlightItemID = nil } }
            )
        ) {
            if let spotlightItemID {
                InventorySpotlightView(
                    store: store,
                    items: items,
                    initialID: spotlightItemID
                )
            }
        }
        .confirmationDialog(
            "Eintrag wirklich löschen?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletionTarget
        ) { item in
            Button("Löschen", role: .destructive) {
                Task {
                    let deleted = await store.deleteItem(kind: item.kind, id: item.id)
                    if deleted, store.overviewSelectionByKind[item.kind] == item.id {
                        store.updateOverviewSelection(nil, for: item.kind)
                    }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { item in
            Text("„\(item.name)“ und die zugehörigen Fotos werden gelöscht. Verknüpfungen werden gelöst.")
        }
    }

    @ViewBuilder
    private func inventoryTable(_ items: [InventoryItemSummary]) -> some View {
        switch store.selectedKind {
        case .board:
            configuredTable(
                items,
                Table(items, selection: selectionBinding, sortOrder: tableSortOrder) {
                    TableColumn("Keyboard", sortUsing: InventorySort(.name)) { row in
                        itemCell(row)
                    }
                    .width(min: 148, ideal: 235)
                    TableColumn("Hersteller", sortUsing: InventorySort(.manufacturer)) { row in
                        Text(row.manufacturer)
                    }
                    .width(min: 70, ideal: 130)
                    TableColumn("Format", sortUsing: InventorySort(.primaryDetail)) { row in
                        Text(row.format)
                    }
                    .width(min: 50, ideal: 80)
                    TableColumn("Switches", sortUsing: InventorySort(.switches)) { row in
                        summaryCell(row.switchesSummary)
                    }
                    .width(min: 88, ideal: 210)
                    TableColumn("Keycaps", sortUsing: InventorySort(.keycaps)) { row in
                        summaryCell(row.keycapsSummary)
                    }
                    .width(min: 85, ideal: 185)
                    photoCountColumn
                }
            )
        case .keycapSet, .artisanSet:
            let nameTitle: LocalizedStringKey = store.selectedKind == .keycapSet ? "Set" : "Artisan"
            let contentsTitle: LocalizedStringKey = store.selectedKind == .keycapSet ? "Kits" : "Tags"
            configuredTable(
                items,
                Table(items, selection: selectionBinding, sortOrder: tableSortOrder) {
                    TableColumn(nameTitle, sortUsing: InventorySort.name) { row in
                        itemCell(row)
                    }
                    .width(min: 148, ideal: 235)
                    TableColumn("Hersteller", sortUsing: InventorySort(.manufacturer)) { row in
                        Text(row.manufacturer)
                    }
                    .width(min: 70, ideal: 130)
                    TableColumn("Profil", sortUsing: InventorySort(.primaryDetail)) { row in
                        Text(row.profile)
                    }
                    .width(min: 50, ideal: 85)
                    TableColumn(contentsTitle, sortUsing: InventorySort(.contents)) { row in
                        summaryCell(row.contentsSummary)
                    }
                    .width(min: 90, ideal: 245)
                    TableColumn("Board", sortUsing: InventorySort(.mountedBoard)) { row in
                        summaryCell(row.mountedBoardSummary)
                    }
                    .width(min: 80, ideal: 155)
                    photoCountColumn
                }
            )
        case .switchSet:
            configuredTable(
                items,
                Table(items, selection: selectionBinding, sortOrder: tableSortOrder) {
                    TableColumn("Name", sortUsing: InventorySort(.name)) { row in
                        itemCell(row)
                    }
                    .width(min: 148, ideal: 235)
                    stockColumn(.quantity, value: \.quantity)
                    stockColumn(.installedQuantity, value: \.installedQuantity)
                    stockColumn(.availableQuantity, value: \.availableQuantity)
                    TableColumn("Typ", sortUsing: InventorySort(.primaryDetail)) { row in
                        Text(row.switchType)
                    }
                    .width(min: 65, ideal: 105)
                    TableColumn("Board", sortUsing: InventorySort(.mountedBoard)) { row in
                        summaryCell(row.mountedBoardSummary)
                    }
                    .width(min: 90, ideal: 210)
                    TableColumn("Betätigungskraft", sortUsing: InventorySort(.operatingForce)) { row in
                        Text(row.operatingForce)
                    }
                    .width(min: 82, ideal: 120)
                    photoCountColumn
                }
            )
        }
    }

    private func itemCell(_ item: InventoryItemSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                openDetails(item)
            } label: {
                ZStack {
                    if let record = store.photoRecord(id: item.mainPhotoID ?? item.photoIDs.first) {
                        ManagedPhotoView(store: store, record: record, purpose: .thumbnail, showsCompactPlaceholder: true)
                    } else {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Kein Foto")
                    }
                }
                .frame(width: 36, height: 26)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Details zu %@ öffnen", arguments: item.name))

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !item.secondaryDetail.isEmpty {
                    Text(item.secondaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
        .help([item.name, item.secondaryDetail].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private var photoCountColumn: TableColumn<InventoryItemSummary, InventorySort, some View, Text> {
        TableColumn("Fotos", sortUsing: InventorySort(.photoCount)) { row in
            Text(row.photoCount, format: .number)
                .monospacedDigit()
        }
        .width(min: 60, ideal: 66, max: 84)
    }

    private func configuredTable<Content: View>(_ items: [InventoryItemSummary], _ table: Content) -> some View {
        table
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first, let item = items.first(where: { $0.id == id }) {
                    itemActions(item)
                }
            } primaryAction: { selectedIDs in
                if let id = selectedIDs.first, let item = items.first(where: { $0.id == id }) {
                    openDetails(item)
                }
            }
            .background {
                OverviewTableFocusBridge(
                    restoreRequest: activeRestoreRequest,
                    selectedRow: activeRestoreRequest?.itemID.flatMap { id in items.firstIndex { $0.id == id } },
                    rowCount: items.count
                ) { offset in
                    store.updateOverviewScrollOffset(offset, for: store.selectedKind)
                } onRestoreApplied: { revision in
                    store.consumeOverviewRestoreRequest(revision: revision)
                }
            }
            .accessibilityIdentifier("overview.table")
    }

    @ViewBuilder
    private func itemActions(_ item: InventoryItemSummary?) -> some View {
        Group {
            Button("Details", systemImage: "eye") {
                if let item { openDetails(item) }
            }
            Button("Bearbeiten", systemImage: "pencil") {
                if let item { store.editItem(kind: item.kind, id: item.id) }
            }
            Button("Name kopieren", systemImage: "doc.on.doc") {
                if let item { copyToPasteboard(item.name) }
            }
            Button("Löschen", systemImage: "trash", role: .destructive) {
                if let item {
                    store.updateOverviewSelection(item.id, for: item.kind)
                    deletionTarget = item
                }
            }
        }
        .disabled(item == nil)
    }

    private func openDetails(_ item: InventoryItemSummary) {
        store.updateOverviewSelection(item.id, for: item.kind)
        spotlightItemID = item.id
    }

    @ViewBuilder
    private func summaryCell(_ value: String) -> some View {
        if value.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(value)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func stockColumn(
        _ field: InventorySort.Field, value: KeyPath<InventoryItemSummary, Int?>
    ) -> TableColumn<InventoryItemSummary, InventorySort, some View, Text> {
        TableColumn(Text(verbatim: field.title(for: .switchSet)), sortUsing: InventorySort(field)) { row in
            Text(row[keyPath: value] ?? 0, format: .number)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .width(min: 70, ideal: 82, max: 105)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch store.editorSaveState {
        case let .saved(message):
            statusRow(message: message, symbol: "checkmark.circle.fill", color: .green)
        case let .failed(message):
            statusRow(message: message, symbol: "exclamationmark.triangle.fill", color: .red)
        case .idle, .saving:
            EmptyView()
        }
    }

    private func statusRow(message: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
                    .help(message)
                Spacer()
                Button("Schließen", systemImage: "xmark") { store.clearEditorStatus() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }

    private var currentSelection: String? {
        store.overviewSelectionByKind[store.selectedKind]
    }

    private var tableSortOrder: Binding<[InventorySort]> {
        let kind = store.selectedKind
        return Binding(
            get: {
                let sort = store.overviewSortsByKind[kind, default: .name]
                return sort.field == .updatedAt ? [] : [sort]
            },
            set: { descriptors in
                guard store.selectedKind == kind, let first = descriptors.first else { return }
                store.collectionSort = first
            }
        )
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { currentSelection },
            set: { store.updateOverviewSelection($0, for: store.selectedKind) }
        )
    }

    private var activeRestoreRequest: OverviewRestoreRequest? {
        guard store.overviewRestoreRequest?.kind == store.selectedKind else {
            return nil
        }
        return store.overviewRestoreRequest
    }

}

@MainActor
struct OverviewTableFocusBridge: NSViewRepresentable {
    var restoreRequest: OverviewRestoreRequest?
    var selectedRow: Int?
    var rowCount: Int
    var onScrollOffsetChange: (Double) -> Void
    var onRestoreApplied: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrollOffsetChange: onScrollOffsetChange,
            onRestoreApplied: onRestoreApplied
        )
    }

    func makeNSView(context: Context) -> TableLocatorView {
        let view = TableLocatorView()
        view.onResolve = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.resolveTable(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: TableLocatorView, context: Context) {
        context.coordinator.update(
            restoreRequest: restoreRequest,
            selectedRow: selectedRow,
            rowCount: rowCount,
            onScrollOffsetChange: onScrollOffsetChange,
            onRestoreApplied: onRestoreApplied
        )
        context.coordinator.resolveTable(from: nsView)
    }

    static func dismantleNSView(_ nsView: TableLocatorView, coordinator: Coordinator) {
        nsView.onResolve = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private var restoreRequest: OverviewRestoreRequest?
        private var selectedRow: Int?
        private var rowCount = 0
        private var onScrollOffsetChange: (Double) -> Void
        private var onRestoreApplied: (Int) -> Void
        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private var lastAppliedRevision = 0
        private var isApplyingRestore = false

        init(
            onScrollOffsetChange: @escaping (Double) -> Void,
            onRestoreApplied: @escaping (Int) -> Void
        ) {
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onRestoreApplied = onRestoreApplied
        }

        func update(
            restoreRequest: OverviewRestoreRequest?,
            selectedRow: Int?,
            rowCount: Int,
            onScrollOffsetChange: @escaping (Double) -> Void,
            onRestoreApplied: @escaping (Int) -> Void
        ) {
            self.restoreRequest = restoreRequest
            self.selectedRow = selectedRow
            self.rowCount = rowCount
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onRestoreApplied = onRestoreApplied
            applyRestoreIfNeeded()
        }

        func resolveTable(from anchor: NSView) {
            guard let contentView = anchor.window?.contentView,
                  let table = findInventoryTable(in: contentView) else {
                return
            }
            if tableView !== table {
                detach()
                tableView = table
                let clipView = table.enclosingScrollView?.contentView
                self.clipView = clipView
                clipView?.postsBoundsChangedNotifications = true
                if let clipView {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(scrollBoundsDidChange(_:)),
                        name: NSView.boundsDidChangeNotification,
                        object: clipView
                    )
                }
            }
            applyRestoreIfNeeded()
        }

        func detach() {
            if let clipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            tableView = nil
            clipView = nil
        }

        @objc
        private func scrollBoundsDidChange(_ notification: Notification) {
            guard !isApplyingRestore,
                  let clipView = notification.object as? NSClipView else {
                return
            }
            onScrollOffsetChange(Double(clipView.bounds.origin.y))
        }

        private func applyRestoreIfNeeded() {
            guard let request = restoreRequest,
                  request.revision != lastAppliedRevision,
                  let tableView,
                  let clipView,
                  tableView.numberOfRows == rowCount else {
                return
            }

            isApplyingRestore = true
            defer { isApplyingRestore = false }
            if let offset = request.scrollOffset {
                let maximumOffset = max(
                    0,
                    tableView.bounds.height - clipView.bounds.height
                )
                clipView.scroll(
                    to: NSPoint(
                        x: clipView.bounds.origin.x,
                        y: min(maximumOffset, max(0, offset))
                    )
                )
                tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
            } else if let selectedRow,
                      selectedRow >= 0,
                      selectedRow < tableView.numberOfRows {
                tableView.scrollRowToVisible(selectedRow)
            }

            tableView.window?.makeFirstResponder(tableView)
            lastAppliedRevision = request.revision
            Task { @MainActor [onRestoreApplied] in
                await Task.yield()
                onRestoreApplied(request.revision)
            }
        }

        private func findInventoryTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.numberOfColumns >= 5 {
                return table
            }
            for subview in view.subviews {
                if let table = findInventoryTable(in: subview) {
                    return table
                }
            }
            return nil
        }
    }
}

@MainActor
final class TableLocatorView: NSView {
    var onResolve: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve?()
    }

    override func layout() {
        super.layout()
        onResolve?()
    }
}
