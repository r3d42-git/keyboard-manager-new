import SwiftUI

@main
struct KeyboardManagerApp: App {
    @State private var store: InventoryStore
    @State private var updateController = AppUpdateController()
    @AppStorage(AppLanguage.preferenceKey) private var preferredLanguage = AppLanguage.german.rawValue
    @AppStorage("collectionAppearance") private var appearance = CollectionAppearance.legacyPreference
    private let shouldAdoptStoredLanguage: Bool
    private let viewPreferences: UserDefaults

    init() {
        shouldAdoptStoredLanguage = UserDefaults.standard.object(
            forKey: AppLanguage.preferenceKey
        ) == nil
        let environment = ProcessInfo.processInfo.environment
        if let testRoot = environment["KEYBOARD_MANAGER_UI_TEST_ROOT"], !testRoot.isEmpty {
            let rootURL = URL(fileURLWithPath: testRoot, isDirectory: true)
            let storage = InventoryStorageLayout(rootURL: rootURL)
            viewPreferences = UserDefaults(suiteName: rootURL.lastPathComponent) ?? .standard
            _store = State(
                initialValue: InventoryStore(
                    repository: SQLiteInventoryRepository(databaseURL: storage.currentDatabaseURL),
                    backupExportService: BackupExportService(layout: storage),
                    backupRestoreService: BackupRestoreService(layout: storage),
                    reportExportService: InventoryReportExportService(layout: storage),
                    photoService: PhotoImportService(layout: storage),
                    thumbnailService: ThumbnailService(layout: storage),
                    preferences: viewPreferences
                )
            )
        } else {
            viewPreferences = .standard
            _store = State(initialValue: InventoryStore(preferences: viewPreferences))
        }
    }

    var body: some Scene {
        Window("Keyboard Manager", id: "collection") {
            ContentView(
                store: store,
                updateController: updateController,
                preferredLanguage: $preferredLanguage,
                shouldAdoptStoredLanguage: shouldAdoptStoredLanguage,
                shouldCheckForUpdates: ProcessInfo.processInfo.environment[
                    "KEYBOARD_MANAGER_UI_TEST_ROOT"
                ] == nil
            )
                .frame(minWidth: 900, minHeight: 600)
                .defaultAppStorage(viewPreferences)
                .preferredColorScheme(appearance.colorScheme)
                .environment(
                    \.locale,
                    AppLanguage.normalized(preferredLanguage).locale
                )
        }
        .defaultSize(width: 1220, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            SidebarCommands()
            CollectionCommands()
        }

        Settings {
            SettingsView(
                store: store,
                updateController: updateController,
                preferredLanguage: $preferredLanguage,
                appearance: $appearance
            )
            .preferredColorScheme(appearance.colorScheme)
            .environment(
                \.locale,
                AppLanguage.normalized(preferredLanguage).locale
            )
        }
    }
}

private struct CollectionCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.inventoryWorkspace) private var store

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(L10n.text("Sammlungsfenster zeigen")) { openWindow(id: "collection") }
                .keyboardShortcut("0")
        }

        CommandGroup(replacing: .newItem) {
            Button(store?.selectedKind.newItemTitle ?? L10n.text("Neues Board")) {
                if let store { store.prepareNewItem(store.selectedKind) }
            }
            .keyboardShortcut("n")
            .disabled(store?.canStartEditor != true)

            Menu(L10n.text("Neuer Eintrag")) {
                ForEach(InventoryItemKind.allCases) { kind in
                    Button(kind.newItemTitle) { store?.prepareNewItem(kind) }
                }
            }
            .disabled(store?.canStartEditor != true)
        }

        CommandMenu(L10n.text("Sammlung")) {
            Group {
                Button(AppRoute.overview.title) { store?.requestRoute(.overview) }
                    .keyboardShortcut("1")
                Button(AppRoute.gallery.title) { store?.requestRoute(.gallery) }
                    .keyboardShortcut("2")
                Button(AppRoute.capture.title) { store?.requestRoute(.capture) }
                    .keyboardShortcut("3")
                    .disabled(store?.canStartEditor != true)
                Divider()
                Button(L10n.text("ZIP-Backup erstellen …")) { store?.chooseBackupDestination() }
                    .disabled(store?.canExportBackup != true)
                Button(L10n.text("Sicherung wiederherstellen …")) { store?.requestBackupRestore() }
                    .disabled(store?.canRestoreBackup != true)
                Button(L10n.text("Bestand exportieren …")) { store?.isReportExportPresented = true }
                    .disabled(store?.canExportReport != true)
            }
            .disabled(store == nil || store?.editorSaveState == .saving)
        }
    }
}

private struct InventoryWorkspaceKey: FocusedValueKey {
    typealias Value = InventoryStore
}

extension FocusedValues {
    var inventoryWorkspace: InventoryStore? {
        get { self[InventoryWorkspaceKey.self] }
        set { self[InventoryWorkspaceKey.self] = newValue }
    }
}
