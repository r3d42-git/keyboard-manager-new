import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Bindable var store: InventoryStore
    @State private var selectingFile = false
    @State private var confirmingReplacement = false
    @State private var fileSelectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Sicherung wiederherstellen", systemImage: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))

            switch store.backupRestoreState {
            case .idle:
                Text("Wähle ein ZIP-Backup aus Keyboard Manager. Du kannst den Inhalt vor dem Wiederherstellen prüfen.")
                    .foregroundStyle(.secondary)
            case .preparing:
                ProgressView("Sicherung wird geprüft …")
            case let .ready(preview):
                VStack(alignment: .leading, spacing: 10) {
                    Label(preview.sourceFileName, systemImage: "doc.zipper")
                        .font(.headline)
                        .textSelection(.enabled)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        ForEach(InventoryItemKind.allCases) { kind in
                            GridRow {
                                Text(kind.displayName)
                                Text(preview.counts.value(for: kind), format: .number)
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                        GridRow {
                            Text("Fotos")
                            Text(preview.counts.photos, format: .number)
                        }
                    }
                    .monospacedDigit()
                }
                Text("Beim Wiederherstellen ersetzt diese Sicherung die aktuelle Sammlung. Der bisherige Bestand wird separat aufbewahrt.")
                    .foregroundStyle(.secondary)
            case .installing:
                ProgressView("Sammlung wird wiederhergestellt …")
            case let .succeeded(result):
                Label("Sammlung wiederhergestellt", systemImage: "checkmark.circle")
                    .font(.headline)
                if let previous = result.previousBackupURL {
                    Button("Vorherigen Bestand im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([previous])
                    }
                }
            case let .failed(message):
                Label {
                    Text(message).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }

            if let fileSelectionError {
                Text(fileSelectionError)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if case .ready = store.backupRestoreState {
                    Button("Andere Sicherung …") { selectingFile = true }
                }
                Spacer()
                if case .succeeded = store.backupRestoreState {
                    Button("Fertig") { close() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Abbrechen", role: .cancel) { close() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(store.isBackupRestoreInstalling)
                    switch store.backupRestoreState {
                    case .idle, .failed:
                        Button("Sicherung auswählen …") { selectingFile = true }
                            .keyboardShortcut(.defaultAction)
                    case .ready:
                        Button("Wiederherstellen …") { confirmingReplacement = true }
                            .keyboardShortcut(.defaultAction)
                    default: EmptyView()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.zip]) { selection in
            do {
                let url = try selection.get()
                fileSelectionError = nil
                Task { await store.prepareBackupRestore(from: url) }
            } catch {
                if (error as NSError).code != NSUserCancelledError {
                    fileSelectionError = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Aktuelle Sammlung ersetzen?", isPresented: $confirmingReplacement, titleVisibility: .visible) {
            Button("Sammlung wiederherstellen", role: .destructive) {
                Task { await store.installBackupRestore() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die geprüften Einträge, Verknüpfungen und Fotos werden gemeinsam wiederhergestellt.")
        }
    }

    private func close() {
        Task { await store.cancelBackupRestore() }
    }
}
