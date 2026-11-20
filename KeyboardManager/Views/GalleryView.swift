import AppKit
import SwiftUI

struct GalleryView: View {
    @Bindable var store: InventoryStore
    @State private var spotlightItemID: String?

    var body: some View {
        let items = store.collectionResults
        VStack(spacing: 0) {
            InventoryFilterBar(store: store, kinds: InventoryQuery.galleryKinds, resultCount: items.count)
            GalleryGrid(store: store, items: items, openDetails: openDetails)
        }
        .searchable(text: $store.collectionFilters.searchText, placement: .toolbar, prompt: "Galerie durchsuchen")
        .sheet(
            isPresented: Binding(
                get: { spotlightItemID != nil },
                set: { if !$0 { spotlightItemID = nil } }
            )
        ) {
            if let spotlightItemID {
                InventorySpotlightView(store: store, items: items, initialID: spotlightItemID)
            }
        }
    }

    private func openDetails(_ item: InventoryItemSummary) {
        store.updateOverviewSelection(item.id, for: item.kind)
        spotlightItemID = item.id
    }
}

private struct GalleryGrid: View {
    let store: InventoryStore
    let items: [InventoryItemSummary]
    let openDetails: (InventoryItemSummary) -> Void

    @AppStorage("galleryCardZoom") private var cardZoom = 0.5
    private let gridPadding: CGFloat = 20
    private let columnSpacing: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                InventoryCollectionEmptyView(store: store)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(columns: columns(for: geometry.size.width), alignment: .leading, spacing: 24) {
                            ForEach(items) { item in
                                Button {
                                    openDetails(item)
                                } label: {
                                    GalleryThumbnail(store: store, item: item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Öffnet die Großansicht")
                                .accessibilityIdentifier("gallery.item.\(item.id)")
                                .contextMenu {
                                    Button("Details", systemImage: "eye") {
                                        openDetails(item)
                                    }
                                    Button("Bearbeiten", systemImage: "pencil") {
                                        store.editItem(kind: item.kind, id: item.id)
                                    }
                                    Button("Name kopieren", systemImage: "doc.on.doc") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.name, forType: .string)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, gridPadding)
                        .padding(.vertical, 18)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityIdentifier("gallery.grid")
            }
            zoomBar
                .disabled(items.isEmpty)
        }
    }

    private var zoomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                Image(systemName: "minus")
                    .accessibilityHidden(true)
                Slider(value: $cardZoom, in: 0...1, step: 0.01) {
                    Text("Kartengröße")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 132)
                .accessibilityIdentifier("gallery.zoom")
                .help("Kartengröße")
                Image(systemName: "plus")
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(.bar)
        }
    }

    private func columns(for viewportWidth: CGFloat) -> [GridItem] {
        let availableWidth = max(1, viewportWidth - 2 * gridPadding)
        let minimumWidth = min(142, availableWidth / 2)
        let maximumWidth = min(500, availableWidth)
        // The middle position matches the former adaptive grid's 180–260 pt cards.
        let defaultCount = columnCount(for: 180, in: availableWidth)
        let defaultWidth = min(260, (availableWidth + columnSpacing) / CGFloat(defaultCount) - columnSpacing)
        let zoom = CGFloat(cardZoom)
        let cardWidth: CGFloat
        if zoom <= 0.5 {
            cardWidth = minimumWidth + (defaultWidth - minimumWidth) * (2 * zoom)
        } else {
            cardWidth = defaultWidth + (maximumWidth - defaultWidth) * (2 * zoom - 1)
        }
        let count = zoom == 0.5 ? defaultCount : columnCount(for: cardWidth, in: availableWidth)
        let column = GridItem(.fixed(cardWidth), spacing: columnSpacing, alignment: .top)
        return Array(repeating: column, count: count)
    }

    private func columnCount(for cardWidth: CGFloat, in availableWidth: CGFloat) -> Int {
        max(1, Int(((availableWidth + columnSpacing) / (cardWidth + columnSpacing)).nextUp))
    }
}

private struct GalleryThumbnail: View {
    let store: InventoryStore
    let item: InventoryItemSummary
    @Environment(\.displayScale) private var displayScale

    private var details: String {
        [item.manufacturer, item.primaryDetail, item.secondaryDetail]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 5) {
            Color.clear
                .aspectRatio(1.85, contentMode: .fit)
                .overlay {
                    if let record = store.photoRecord(id: item.mainPhotoID ?? item.photoIDs.first) {
                        GeometryReader { geometry in
                            let pixels = geometry.size.width * displayScale
                            ManagedPhotoView(
                                store: store, record: record,
                                purpose: pixels > CGFloat(ThumbnailService.maximumPixelSize) ? .full : .thumbnail,
                                showsCompactPlaceholder: true
                            )
                            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                        }
                    } else {
                        VStack(spacing: 5) {
                            Image(systemName: item.kind.systemImage)
                                .font(.largeTitle.weight(.light))
                                .accessibilityHidden(true)
                            Text("Kein Foto")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            Text(item.name)
                .font(.body.weight(.medium))
                .lineLimit(2)
            if !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if item.photoCount > 0 || item.externalImageCount > 0 {
                HStack(spacing: 8) {
                    if item.photoCount > 0 {
                        Label(item.photoCount.formatted(), systemImage: "photo")
                            .accessibilityLabel(Text("Fotos"))
                            .accessibilityValue(Text(item.photoCount, format: .number))
                    }
                    if item.externalImageCount > 0 {
                        Label(item.externalImageCount.formatted(), systemImage: "icloud.and.arrow.down")
                            .help("Externe Bilder werden nur auf Wunsch geladen.")
                            .accessibilityLabel(Text("Externe Bilder"))
                            .accessibilityValue(Text(item.externalImageCount, format: .number))
                    }
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .help([item.name, details].filter { !$0.isEmpty }.joined(separator: "\n"))
        .accessibilityElement(children: .combine)
    }
}
