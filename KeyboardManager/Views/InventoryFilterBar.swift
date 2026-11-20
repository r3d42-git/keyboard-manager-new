import SwiftUI

extension InventoryStore {
    // Both presentations browse the same collection and share its search and sort state.
    var collectionFilters: InventoryFilters {
        get { overviewFiltersByKind[selectedKind, default: InventoryFilters()] }
        set { overviewFiltersByKind[selectedKind] = newValue }
    }

    var collectionResults: [InventoryItemSummary] {
        InventoryQuery.results(in: snapshot, kind: selectedKind, filters: collectionFilters, sort: collectionSort)
    }
}

struct InventoryFilterBar: View {
    @Bindable var store: InventoryStore
    let kinds: [InventoryItemKind]
    let resultCount: Int
    @State private var isFiltering = false
    @State private var fitsSegmentedPicker = false

    private var counts: InventoryCounts { store.snapshot.counts }
    private var kind: InventoryItemKind { store.selectedKind }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("Ohne Foto", isOn: $store.collectionFilters.withoutPhoto)
                    .help("Einträge ohne lokales Foto anzeigen")
                    .accessibilityIdentifier("collection.quickFilter.noPhoto")
                if kind.supportsMountFilter {
                    Toggle("Nicht montiert", isOn: $store.collectionFilters.unmountedOnly)
                        .accessibilityIdentifier("collection.quickFilter.unmounted")
                }
                Spacer(minLength: 4)
                if !store.collectionFilters.isEmpty(for: kind) {
                    Text("\(resultCount) von \(counts.value(for: kind))")
                        .monospacedDigit()
                        .fixedSize()
                        .foregroundStyle(.secondary)
                    if !activeValues.isEmpty {
                        Text(activeValues.joined(separator: " · "))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .help(activeValues.joined(separator: ", "))
                    }
                    Button("Filter zurücksetzen") {
                        store.collectionFilters = InventoryFilters()
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider()
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width >= 940
        } action: { fits in
            fitsSegmentedPicker = fits
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if fitsSegmentedPicker {
                    kindPicker
                        .pickerStyle(.segmented)
                        .fixedSize()
                } else {
                    kindPicker
                        .pickerStyle(.menu)
                        .fixedSize()
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                filterControls
            }
        }
        .onChange(of: kind) {
            if store.route == .overview || store.route == .gallery {
                store.selectedItemID = store.overviewSelectionByKind[kind]
            }
        }
    }

    private var kindPicker: some View {
        Picker("Inventartyp", selection: $store.selectedKind) {
            ForEach(kinds) { option in
                Text(verbatim: "\(option.displayName)  \(counts.value(for: option).formatted())")
                    .tag(option)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Inventartyp")
        .help("Inventartyp")
        .accessibilityIdentifier("collection.kind")
    }

    @ViewBuilder
    private var filterControls: some View {
        Button {
            isFiltering.toggle()
        } label: {
            Label("Filter", systemImage: activeValues.isEmpty
                  ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filter")
        .accessibilityIdentifier("collection.filters")
        .popover(isPresented: $isFiltering) {
            filterPopover
        }

        Menu {
            Picker("Sortierung", selection: sortField) {
                ForEach(InventorySort.Field.available(for: kind), id: \.self) { option in
                    Text(option.title(for: kind)).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Reihenfolge", selection: $store.collectionSort.order) {
                Text("Aufsteigend").tag(SortOrder.forward)
                Text("Absteigend").tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sortierung", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sortierung")
        .accessibilityValue(Text(verbatim: sortDescription))
        .help(Text(verbatim: sortDescription))
        .accessibilityIdentifier("collection.sort")
    }

    private var sortField: Binding<InventorySort.Field> {
        Binding(
            get: { store.collectionSort.field },
            set: { field in
                guard field != store.collectionSort.field else { return }
                let order: SortOrder = [.updatedAt, .quantity, .installedQuantity, .availableQuantity].contains(field) ? .reverse : .forward
                store.collectionSort = InventorySort(field, order: order)
            }
        )
    }

    private var sortDescription: String {
        let sort = store.collectionSort
        let direction = sort.order == .forward ? L10n.text("Aufsteigend") : L10n.text("Absteigend")
        return "\(sort.field.title(for: kind)) · \(direction)"
    }

    private var activeValues: [String] {
        let filters = store.collectionFilters
        switch kind {
        case .board:
            return [filters.manufacturer, filters.format].filter { !$0.isEmpty }
        case .keycapSet, .artisanSet:
            return [filters.manufacturer, filters.profile, filters.status].filter { !$0.isEmpty }
        case .switchSet:
            return [filters.switchType, filters.operatingForce, filters.pins?.displayName ?? ""].filter { !$0.isEmpty }
        }
    }

    private var filterPopover: some View {
        let items = InventoryQuery.items(in: store.snapshot, kind: kind)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Filter")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                switch kind {
                case .board:
                    stringPicker("Hersteller", all: "Alle Hersteller",
                                 selection: $store.collectionFilters.manufacturer,
                                 values: InventoryQuery.values(\.manufacturer, in: items))
                    stringPicker("Format", all: "Alle Formate",
                                 selection: $store.collectionFilters.format,
                                 values: InventoryQuery.values(\.format, in: items))
                case .keycapSet, .artisanSet:
                    stringPicker("Hersteller", all: "Alle Hersteller",
                                 selection: $store.collectionFilters.manufacturer,
                                 values: InventoryQuery.values(\.manufacturer, in: items))
                    stringPicker("Profil", all: "Alle Profile",
                                 selection: $store.collectionFilters.profile,
                                 values: InventoryQuery.values(\.profile, in: items))
                    stringPicker("Status", all: "Alle Status",
                                 selection: $store.collectionFilters.status,
                                 values: InventoryQuery.values(\.status, in: items))
                case .switchSet:
                    stringPicker("Typ", all: "Alle Typen",
                                 selection: $store.collectionFilters.switchType,
                                 values: InventoryQuery.values(\.switchType, in: items))
                    stringPicker("Betätigungskraft", all: "Alle Kräfte",
                                 selection: $store.collectionFilters.operatingForce,
                                 values: InventoryQuery.values(\.operatingForce, in: items))
                    GridRow {
                        Text("Pins")
                        Picker("Pins", selection: $store.collectionFilters.pins) {
                            Text("Alle Pins").tag(SwitchPins?.none)
                            ForEach(SwitchPins.allCases) { pins in
                                Text(pins.displayName).tag(Optional(pins))
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            .pickerStyle(.menu)
            Divider()
            HStack {
                Button("Filter zurücksetzen") {
                    store.collectionFilters = InventoryFilters()
                }
                .disabled(store.collectionFilters.isEmpty(for: kind))
                Spacer()
                Button("Fertig") { isFiltering = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    private func stringPicker(
        _ title: LocalizedStringKey,
        all: LocalizedStringKey,
        selection: Binding<String>,
        values: [String]
    ) -> some View {
        GridRow {
            Text(title)
            Picker(title, selection: selection) {
                Text(all).tag("")
                // Keep a previously selected value understandable after editing or deleting its last item.
                if !selection.wrappedValue.isEmpty, !values.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .labelsHidden()
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .help(selection.wrappedValue)
        }
    }
}

struct InventoryCollectionEmptyView: View {
    @Bindable var store: InventoryStore

    var body: some View {
        let isFiltered = !store.collectionFilters.isEmpty(for: store.selectedKind)
        ContentUnavailableView {
            if isFiltered {
                Label("Keine Treffer", systemImage: "magnifyingglass")
            } else {
                Label("Noch keine \(store.selectedKind.displayName)", systemImage: store.selectedKind.systemImage)
            }
        } description: {
            if isFiltered {
                Text("Passe Suche oder Filter an.")
            } else {
                Text("Erfasse deinen ersten Eintrag in dieser Kategorie.")
            }
        } actions: {
            if isFiltered {
                Button("Filter zurücksetzen") {
                    store.collectionFilters = InventoryFilters()
                }
            } else {
                Button("\(store.selectedKind.singularName) erfassen") {
                    store.prepareNewItem(store.selectedKind)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
