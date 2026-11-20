import Foundation

struct InventoryStorageLayout: Hashable, Sendable {
    static let applicationDirectoryName = "de.r3d42.KeyboardManagerV2"

    var rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    static var `default`: InventoryStorageLayout {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return InventoryStorageLayout(
            rootURL: applicationSupport.appendingPathComponent(applicationDirectoryName, isDirectory: true)
        )
    }

    var currentDirectoryURL: URL {
        rootURL.appendingPathComponent("Current", isDirectory: true)
    }

    var currentDatabaseURL: URL {
        currentDirectoryURL.appendingPathComponent("inventory.sqlite")
    }

    var currentPhotosDirectoryURL: URL {
        currentDirectoryURL.appendingPathComponent("Photos", isDirectory: true)
    }

    var currentThumbnailsDirectoryURL: URL {
        currentDirectoryURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }
}
