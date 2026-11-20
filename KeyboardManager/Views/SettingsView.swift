import SwiftUI

struct SettingsView: View {
    @Bindable var store: InventoryStore
    @Bindable var updateController: AppUpdateController
    @Binding var preferredLanguage: String
    @Binding var appearance: CollectionAppearance

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(CollectionAppearance.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Sprache", selection: $preferredLanguage) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                .disabled(store.isBackupRestoreActive)
            }

            Section("Sammlung") {
                LabeledContent("Datenhaltung", value: L10n.text("SQLite · lokal"))
            }

            Section("Updates") {
                LabeledContent("Installierte Version", value: updateController.installedVersion)
                updateStatus
                Button("Nach Updates suchen") {
                    Task {
                        await updateController.checkForUpdates()
                    }
                }
                .disabled(updateController.isWorking)
            }

            if let message = store.languagePersistenceError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 410)
        .navigationTitle("Allgemein")
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateController.state {
        case .idle:
            Text("Beim Start wird nach stabilen GitHub-Releases gesucht.")
                .foregroundStyle(.secondary)
        case .checking:
            Label("Suche nach Updates …", systemImage: "arrow.triangle.2.circlepath")
        case .upToDate:
            Label("Die App ist aktuell.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .updateAvailable(update):
            HStack {
                Label("Version \(update.version.description) ist verfügbar.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Laden") {
                    Task {
                        await updateController.downloadAndOpen(update)
                    }
                }
            }
        case .downloading:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Installer wird geladen und geprüft …")
            }
        case let .installerOpened(update, url):
            Label(
                "Version \(update.version.description) wurde geprüft und geöffnet: \(url.lastPathComponent)",
                systemImage: "checkmark.shield.fill"
            )
            .foregroundStyle(.green)
        case let .failed(message):
            Label("Updateprüfung fehlgeschlagen: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}


enum CollectionAppearance: String, CaseIterable {
    case system, light, dark

    static var legacyPreference: Self {
        (UserDefaults.standard.object(forKey: "followSystemAppearance") as? Bool) == false ? .light : .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }
}
