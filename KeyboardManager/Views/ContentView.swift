import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: InventoryStore
    @Bindable var updateController: AppUpdateController
    @Binding var preferredLanguage: String
    let shouldAdoptStoredLanguage: Bool
    let shouldCheckForUpdates: Bool
    @State private var didInitializeLanguage = false
    @State private var isUpdateAlertPresented = false
    @State private var loadAttempt = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 170, ideal: 208, max: 280)
        } detail: {
            VStack(spacing: 0) {
                detailView
                    .id(store.backupRestoreRevision)
                reportExportStatus
                backupExportStatus
            }
            .navigationTitle(store.route.title)
            .toolbar {
                if store.route == .overview || store.route == .gallery {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.prepareNewItem(store.selectedKind)
                        } label: {
                            Label(store.selectedKind.newItemTitle, systemImage: "plus")
                        }
                        .accessibilityLabel(Text(store.selectedKind.newItemTitle))
                        .disabled(!store.canStartEditor)
                        .help(store.selectedKind.newItemTitle)
                        .accessibilityIdentifier("collection.new")
                    }
                }
            }
        }
        .sheet(isPresented: $store.isReportExportPresented) {
            InventoryReportExportView(currentKind: store.selectedKind) { options in
                let context = InventoryReportContext(
                    currentKind: store.selectedKind,
                    filtersByKind: store.overviewFiltersByKind,
                    sortsByKind: store.overviewSortsByKind
                )
                guard let destination = InventoryReportSavePanel.chooseDestination(for: options.format) else { return }
                Task { await store.exportReport(context: context, options: options, to: destination) }
            }
        }
        .sheet(isPresented: $store.isBackupRestorePresented) {
            BackupRestoreView(store: store)
                .interactiveDismissDisabled()
        }
        .focusedSceneValue(\.inventoryWorkspace, store)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard Manager Hauptfenster")
        .contextMenu {
            Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                performResponderAction(Selector(("undo:")))
            }
            .disabled(!canPerformResponderAction(Selector(("undo:"))))
            Button("Wiederholen", systemImage: "arrow.uturn.forward") {
                performResponderAction(Selector(("redo:")))
            }
            .disabled(!canPerformResponderAction(Selector(("redo:"))))

            Divider()

            Button("Ausschneiden", systemImage: "scissors") {
                performResponderAction(#selector(NSText.cut(_:)))
            }
            .disabled(!canPerformResponderAction(#selector(NSText.cut(_:))))
            Button("Kopieren", systemImage: "doc.on.doc") {
                performResponderAction(#selector(NSText.copy(_:)))
            }
            .disabled(!canPerformResponderAction(#selector(NSText.copy(_:))))
            Button("Einfügen", systemImage: "doc.on.clipboard") {
                performResponderAction(#selector(NSText.paste(_:)))
            }
            .disabled(!canPerformResponderAction(#selector(NSText.paste(_:))))

            Divider()

            Button("Alles auswählen", systemImage: "textformat") {
                performResponderAction(#selector(NSText.selectAll(_:)))
            }
            .disabled(!canPerformResponderAction(#selector(NSText.selectAll(_:))))
        }
        .task(id: loadAttempt) {
            await store.load()
            guard store.loadState == .loaded else { return }
            if shouldAdoptStoredLanguage {
                preferredLanguage = AppLanguage.normalized(
                    store.snapshot.metadata.preferredLanguage
                ).rawValue
            } else {
                preferredLanguage = AppLanguage.normalized(preferredLanguage).rawValue
            }
            await store.updatePreferredLanguage(preferredLanguage)
            didInitializeLanguage = true
            if shouldCheckForUpdates {
                await updateController.checkForUpdates()
            }
        }
        .onChange(of: preferredLanguage) { _, newValue in
            guard didInitializeLanguage else { return }
            Task {
                await store.updatePreferredLanguage(newValue)
            }
        }
        .onChange(of: store.snapshot.metadata.preferredLanguage) { _, storedValue in
            guard didInitializeLanguage,
                  AppLanguage.normalized(storedValue).rawValue
                    != AppLanguage.normalized(preferredLanguage).rawValue else {
                return
            }
            Task {
                await store.updatePreferredLanguage(preferredLanguage)
            }
        }
        .background {
            WindowCloseGuard(
                closeRevision: store.windowCloseRevision,
                shouldAllowClose: store.shouldAllowWindowClose
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: updateController.availableUpdate) { _, update in
            isUpdateAlertPresented = update != nil
        }
        .alert(
            "Update verfügbar",
            isPresented: $isUpdateAlertPresented,
            presenting: updateController.availableUpdate
        ) { update in
            Button("Jetzt laden") {
                Task {
                    await updateController.downloadAndOpen(update)
                }
            }
            Button("Später", role: .cancel) {}
        } message: { update in
            Text(
                "Version \(update.version.description) ist verfügbar. Der Installer wird vor dem Öffnen gegen die veröffentlichte SHA-256-Prüfsumme geprüft."
            )
        }
        .confirmationDialog(
            "Fenster mit ungespeicherten Änderungen schließen?",
            isPresented: $store.isWindowCloseConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen und schließen", role: .destructive) {
                store.confirmDiscardAndCloseWindow()
            }
            Button("Weiter bearbeiten", role: .cancel) {
                store.cancelWindowClose()
            }
        } message: {
            Text("Der aktuelle Entwurf wurde noch nicht gespeichert.")
        }
    }

    @ViewBuilder
    private var reportExportStatus: some View {
        switch store.reportExportState {
        case .idle:
            EmptyView()
        case let .exporting(format):
            statusBar {
                ProgressView()
                    .controlSize(.small)
                Text("\(format.title)-Bestandsbericht wird erstellt und kontrolliert …")
            }
        case let .succeeded(result):
            statusBar {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(L10n.text("Bericht gespeichert: %@ · %@", arguments: result.destinationURL.lastPathComponent,
                               result.byteCount.formatted(.byteCount(style: .file))))
                Text(result.itemCount == 1 ? L10n.text("1 Eintrag") : L10n.text("%lld Einträge", arguments: result.itemCount))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.destinationURL])
                }
                Button("Schließen") {
                    store.clearReportExportStatus()
                }
            }
        case let .failed(message):
            statusBar {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Bericht fehlgeschlagen: \(message)")
                    .lineLimit(2)
                Spacer()
                Button("Schließen") {
                    store.clearReportExportStatus()
                }
            }
        }
    }

    @ViewBuilder
    private var backupExportStatus: some View {
        switch store.backupExportState {
        case .idle:
            EmptyView()
        case .exporting:
            statusBar {
                ProgressView()
                    .controlSize(.small)
                Text("ZIP-Backup wird erstellt und kontrolliert …")
            }
        case let .succeeded(result):
            statusBar {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(
                    L10n.text("Backup gespeichert: %@ · %@", arguments: result.destinationURL.lastPathComponent,
                              result.byteCount.formatted(.byteCount(style: .file)))
                )
                if result.transcodedHEICPhotoCount > 0 {
                    Text("· \(result.transcodedHEICPhotoCount) HEIC als JPEG kopiert")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.destinationURL])
                }
                Button("Schließen") {
                    store.clearBackupExportStatus()
                }
            }
        case let .failed(message):
            statusBar {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Backup fehlgeschlagen: \(message)")
                    .lineLimit(2)
                Spacer()
                Button("Schließen") {
                    store.clearBackupExportStatus()
                }
            }
        }
    }

    private func statusBar<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8, content: content)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
    }

    private func performResponderAction(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    private func canPerformResponderAction(_ action: Selector) -> Bool {
        NSApp.target(forAction: action, to: nil, from: nil) != nil
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView("Sammlung wird geöffnet …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Sammlung konnte nicht geöffnet werden", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                HStack {
                    Button("Erneut versuchen") {
                        store.loadState = .idle
                        loadAttempt += 1
                    }
                    Button("Sicherung wiederherstellen …") { store.requestBackupRestore() }
                        .disabled(!store.canRestoreBackup)
                }
            }
        case .loaded:
            switch store.route {
            case .overview: OverviewView(store: store)
            case .capture: CaptureView(store: store)
            case .gallery: GalleryView(store: store)
            }
        }
    }
}
