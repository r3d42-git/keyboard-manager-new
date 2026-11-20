import SwiftUI

struct SidebarView: View {
    @Bindable var store: InventoryStore

    var body: some View {
        List(selection: routeSelection) {
            Section("Sammlung") {
                ForEach(AppRoute.primary) { route in
                    Label(route.title, systemImage: route.systemImage)
                        .tag(route)
                        .accessibilityIdentifier("sidebar.\(route.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 26)
        .id(store.navigationRevision)
        .navigationTitle("Keyboard Manager")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 3)

                    utilityButton("Bericht exportieren …", symbol: "doc.text", id: "sidebar.report") {
                        store.isReportExportPresented = true
                    }
                    .disabled(!store.canExportReport)

                    utilityButton("Backup erstellen …", symbol: "externaldrive.badge.plus", id: "sidebar.backup") {
                        store.chooseBackupDestination()
                    }
                    .disabled(!store.canExportBackup)

                    utilityButton("Backup einspielen …", symbol: "arrow.counterclockwise", id: "sidebar.restore") {
                        store.requestBackupRestore()
                    }
                    .disabled(!store.canRestoreBackup)
                }
                .padding(10)

                if store.loadState == .loaded {
                    Text(collectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
        }
        .disabled(store.editorSaveState == .saving)
    }

    private func utilityButton(
        _ title: LocalizedStringKey, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title).lineLimit(1)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.accessoryBar)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(id)
        .help(Text(title))
    }

    private var collectionSummary: String {
        let counts = store.snapshot.counts
        let entries = counts.totalItems == 1 ? L10n.text("1 Eintrag") : L10n.text("%lld Einträge", arguments: counts.totalItems)
        let photos = counts.photos == 1 ? L10n.text("1 Foto") : L10n.text("%lld Fotos", arguments: counts.photos)
        return "\(entries) · \(photos)"
    }

    private var routeSelection: Binding<AppRoute?> {
        Binding(
            get: { store.route },
            set: { route in
                if let route { store.requestRoute(route) }
            }
        )
    }
}
