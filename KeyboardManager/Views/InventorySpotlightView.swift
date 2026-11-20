import AppKit
import SwiftUI

private struct SpotlightRelation: Identifiable {
    let kind: InventoryItemKind
    let id: String
    let title: String
}

private struct SpotlightLinkedDetail {
    let item: InventoryItemSummary
    let boardPhotoID: String?
}

struct InventorySpotlightView: View {
    @Bindable var store: InventoryStore
    var items: [InventoryItemSummary]

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var linkedDetail: SpotlightLinkedDetail?
    @State private var selectedPhotoID: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var largePhotoWindow = InventoryLargePhotoWindowController()

    init(
        store: InventoryStore,
        items: [InventoryItemSummary],
        initialID: String
    ) {
        self.store = store
        self.items = items
        _currentID = State(initialValue: initialID)
        let initialItem = items.first { $0.id == initialID }
        _selectedPhotoID = State(initialValue: initialItem?.mainPhotoID ?? initialItem?.photoIDs.first)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()

            if let item = currentItem {
                HStack(spacing: 0) {
                    photoArea(for: item)

                    Divider()

                    detailInspector(for: item)
                        .frame(width: 282)
                        .id(item.id)
                        .id(item.kind)
                }
            } else {
                ContentUnavailableView(
                    "Eintrag nicht mehr verfügbar",
                    systemImage: "questionmark.folder"
                )
            }
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 510, idealHeight: 620)
        .background {
            SpotlightWindowReference { window in
                largePhotoWindow.parentWindow = window
            }
            .frame(width: 0, height: 0)
        }
        .onExitCommand {
            dismiss()
        }
        .confirmationDialog(
            "Eintrag wirklich löschen?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let item = currentItem else { return }
                Task {
                    if await store.deleteItem(kind: item.kind, id: item.id) {
                        dismiss()
                    }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Eintrag, seine Fotos und seine Beziehungen werden konsistent entfernt.")
        }
        .onDisappear {
            largePhotoWindow.close()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            if linkedDetail != nil {
                Button("Zurück zum Keyboard", systemImage: "chevron.backward", action: returnToBoard)
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityIdentifier("spotlight-back-to-board")
            } else {
                HStack(spacing: 4) {
                    Button {
                        stepItemOrLargePhoto(by: -1)
                    } label: {
                        Label("Vorheriger Eintrag", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Vorheriger Eintrag")

                    Button {
                        stepItemOrLargePhoto(by: 1)
                    } label: {
                        Label("Nächster Eintrag", systemImage: "chevron.right")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Nächster Eintrag")
                }
                .labelStyle(.iconOnly)
                .disabled(items.count < 2)

                Text(positionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if let item = currentItem {
                Button("Groß ansehen", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showLargePhoto(for: item)
                }
                .labelStyle(.iconOnly)
                .help("Foto groß ansehen")
                .disabled(selectedPhoto(for: item) == nil)

                Button("Bearbeiten", systemImage: "pencil") {
                    edit(item)
                }

                Button("Löschen", systemImage: "trash", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .labelStyle(.iconOnly)
                .help("Löschen")
            }

            Button("Schließen", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .help("Schließen")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func photoArea(for item: InventoryItemSummary) -> some View {
        let photo = selectedPhoto(for: item)
        return VStack(spacing: 12) {
            Group {
                if let photo {
                    Button {
                        showLargePhoto(for: item)
                    } label: {
                        ManagedPhotoView(store: store, record: photo, purpose: .full)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Foto in Großansicht öffnen")
                    .help("Foto groß ansehen")
                } else if item.externalImageCount > 0 {
                    ContentUnavailableView {
                        Label("Externes Importbild", systemImage: "icloud.and.arrow.down")
                    } description: {
                        Text("Externe Bildadressen werden aus Datenschutzgründen nicht automatisch geladen.")
                    } actions: {
                        Button("Zum lokalen Übernehmen bearbeiten") {
                            edit(item)
                        }
                    }
                } else {
                    ContentUnavailableView("Kein Foto", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.55))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary)
                    .allowsHitTesting(false)
            }

            if item.photoCount > 1 {
                photoNavigation(for: item)
                    .id(item.id)
            }
        }
        .padding(16)
    }

    private func photoNavigation(for item: InventoryItemSummary) -> some View {
        let activePhotoID = activePhotoID(for: item)
        let currentIndex = item.photoIDs.firstIndex { $0 == activePhotoID } ?? 0

        return HStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(item.photoIDs.enumerated()), id: \.element) { index, photoID in
                            thumbnail(
                                for: photoID,
                                index: index,
                                isMain: photoID == item.mainPhotoID,
                                isSelected: photoID == activePhotoID
                            )
                            .id(photoID)
                        }
                    }
                    .padding(2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 58)
                .onChange(of: activePhotoID, initial: true) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            InventoryPhotoStepper(
                index: currentIndex,
                count: item.photoCount,
                step: { offset in
                    let index = currentIndex + offset
                    guard item.photoIDs.indices.contains(index) else { return }
                    selectedPhotoID = item.photoIDs[index]
                }
            )
        }
    }

    private func thumbnail(for photoID: String, index: Int, isMain: Bool, isSelected: Bool) -> some View {
        let title = isMain
            ? L10n.text("Foto %lld (Hauptfoto)", arguments: index + 1)
            : L10n.text("Foto %lld", arguments: index + 1)

        return Button {
            selectedPhotoID = photoID
        } label: {
            ManagedPhotoView(
                store: store,
                record: store.photoRecord(id: photoID),
                purpose: .thumbnail,
                showsCompactPlaceholder: true
            )
            .frame(width: 72, height: 52)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("spotlight-photo-\(photoID)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(title)
    }

    private func detailInspector(for item: InventoryItemSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(item.kind.singularName, systemImage: item.kind.systemImage)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(item.name)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("spotlight-title")
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.metadata.filter { $0.relationshipKind == nil && !$0.value.isEmpty }, id: \.self) { field in
                        detailRow(Text(field.label)) {
                            Text(field.value)
                                .textSelection(.enabled)
                        }
                    }
                    if item.kind == .board, let board = store.snapshot.boards.first(where: { $0.id == item.id }) {
                        boardRelationships(for: board)
                    }
                    detailRow(Text("Lokale Fotos")) {
                        Text(item.photoCount, format: .number)
                            .monospacedDigit()
                    }
                    if item.externalImageCount > 0 {
                        detailRow(Text("Externe Importbilder")) {
                            Text(item.externalImageCount, format: .number)
                                .monospacedDigit()
                        }
                    }
                }

                if !item.notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notizen")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.notes)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                if let url = validatedHTTPSURL(item.sourceURL) {
                    Divider()
                    Button("Quelle im Browser öffnen", systemImage: "safari") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func detailRow<Content: View>(_ label: Text, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            label
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var currentItem: InventoryItemSummary? {
        linkedDetail?.item ?? items.first { $0.id == currentID }
    }

    private var currentIndex: Int? {
        items.firstIndex { $0.id == currentID }
    }

    private var positionText: String {
        guard let currentIndex else {
            return L10n.text("0 von %lld", arguments: items.count)
        }
        return L10n.text(
            "%lld von %lld",
            arguments: currentIndex + 1,
            items.count
        )
    }

    private func selectedPhoto(for item: InventoryItemSummary) -> PhotoRecord? {
        store.photoRecord(id: activePhotoID(for: item))
    }

    private func activePhotoID(for item: InventoryItemSummary) -> String? {
        if let selectedPhotoID, item.photoIDs.contains(selectedPhotoID) {
            return selectedPhotoID
        }
        return item.mainPhotoID ?? item.photoIDs.first
    }

    @ViewBuilder
    private func boardRelationships(for board: Board) -> some View {
        let snapshot = store.snapshot
        let keycapsByID = Dictionary(uniqueKeysWithValues: snapshot.keycapSets.map { ($0.id, $0.name) })
        let keycaps = board.keycapSetIDs.compactMap { id in
            keycapsByID[id].map { SpotlightRelation(kind: .keycapSet, id: id, title: $0) }
        }
        let artisans = snapshot.artisanSets.filter { $0.mountedBoardID == board.id }.map {
            SpotlightRelation(kind: .artisanSet, id: $0.id, title: $0.name)
        }
        let switchesByID = Dictionary(uniqueKeysWithValues: snapshot.switchSets.map { ($0.id, $0.name) })
        let switches = snapshot.switchInstallations.filter { $0.boardID == board.id }.compactMap { installation in
            switchesByID[installation.switchSetID].map { name in
                SpotlightRelation(
                    kind: .switchSet,
                    id: installation.switchSetID,
                    title: L10n.text("%@ · %lld Stück", arguments: name, installation.quantity)
                )
            }
        }

        relationshipGroup("Keycaps", links: keycaps, fallback: board.legacyKeycapsName)
        relationshipGroup("Artisans", links: artisans)
        relationshipGroup("Switches", links: switches, fallback: board.legacySwitchesName)
    }

    @ViewBuilder
    private func relationshipGroup(_ label: LocalizedStringKey, links: [SpotlightRelation], fallback: String = "") -> some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .foregroundStyle(.secondary)
                ForEach(links) { link in
                    Button {
                        openRelatedItem(link)
                    } label: {
                        Text(link.title)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("spotlight-related-\(link.kind.rawValue)-\(link.id)")
                }
            }
        } else if !fallback.isEmpty {
            detailRow(Text(label)) {
                Text(fallback)
                    .textSelection(.enabled)
            }
        }
    }

    private func openRelatedItem(_ link: SpotlightRelation) {
        guard let board = currentItem, board.kind == .board,
              let item = InventoryQuery.items(in: store.snapshot, kind: link.kind).first(where: { $0.id == link.id }) else {
            return
        }
        largePhotoWindow.close()
        linkedDetail = SpotlightLinkedDetail(item: item, boardPhotoID: activePhotoID(for: board))
        selectedPhotoID = item.mainPhotoID ?? item.photoIDs.first
    }

    private func returnToBoard() {
        largePhotoWindow.close()
        selectedPhotoID = linkedDetail?.boardPhotoID
        linkedDetail = nil
    }

    private func stepItemOrLargePhoto(by offset: Int) {
        guard !largePhotoWindow.stepPhotoIfPresented(by: offset), linkedDetail == nil, let currentIndex else { return }
        select(items[(currentIndex + offset + items.count) % items.count])
    }

    private func select(_ item: InventoryItemSummary) {
        currentID = item.id
        selectedPhotoID = item.mainPhotoID ?? item.photoIDs.first
    }

    private func showLargePhoto(for item: InventoryItemSummary) {
        let selection = $selectedPhotoID
        largePhotoWindow.present(
            store: store,
            item: item,
            selectedPhotoID: activePhotoID(for: item),
            onPhotoSelection: { selection.wrappedValue = $0 }
        )
    }

    private func edit(_ item: InventoryItemSummary) {
        dismiss()
        store.editItem(kind: item.kind, id: item.id)
    }

    private func validatedHTTPSURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil else {
            return nil
        }
        return components.url
    }
}

enum ManagedPhotoPurpose: Hashable {
    case thumbnail
    case full
}

struct ManagedPhotoView: View {
    @Bindable var store: InventoryStore
    var record: PhotoRecord?
    var purpose: ManagedPhotoPurpose
    var showsCompactPlaceholder = false

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if showsCompactPlaceholder {
                VStack(spacing: 2) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .regular))
                    Text("Kein Foto")
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kein Foto")
            } else {
                ContentUnavailableView {
                    Label("Kein Foto", systemImage: "photo")
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskID) {
            await loadImage()
        }
    }

    private var taskID: String {
        "\(record?.id ?? "none")::\(purpose)"
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let record else {
            isLoading = false
            return
        }
        isLoading = true
        let data: Data?
        switch purpose {
        case .thumbnail:
            data = await store.thumbnailData(for: record)
        case .full:
            data = await store.photoData(for: record)
        }
        guard !Task.isCancelled else { return }
        image = data.flatMap(NSImage.init(data:))
        isLoading = false
    }
}
