import Darwin
import Foundation

struct BackupRestorePreview: Equatable, Sendable {
    let sourceFileName: String
    let counts: InventoryCounts
}

struct BackupRestoreResult: Equatable, Sendable {
    let counts: InventoryCounts
    let previousBackupURL: URL?
}

enum BackupRestoreState: Equatable, Sendable {
    case idle
    case preparing
    case ready(BackupRestorePreview)
    case installing
    case succeeded(BackupRestoreResult)
    case failed(String)
}

enum BackupRestoreError: LocalizedError {
    case alreadyPreparing
    case noPreparedBackup
    case invalidSource
    case sourceTooLarge
    case sourceChanged
    case unsafeStorageDirectory
    case currentDataChanged
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .alreadyPreparing:
            L10n.text("Eine Wiederherstellung ist bereits vorbereitet oder läuft.")
        case .noPreparedBackup:
            L10n.text("Es ist kein Backup zur Wiederherstellung vorbereitet.")
        case .invalidSource:
            L10n.text("Bitte ein lesbares ZIP-Backup auswählen.")
        case .sourceTooLarge:
            L10n.text("Das Backup überschreitet das Limit von 500 MiB.")
        case .sourceChanged:
            L10n.text("Die ZIP-Datei hat sich während der Vorbereitung geändert.")
        case .unsafeStorageDirectory:
            L10n.text("Der Datenordner kann nicht sicher ausgetauscht werden.")
        case .currentDataChanged:
            L10n.text("Der aktuelle Bestand hat sich geändert. Bitte das Backup erneut prüfen.")
        case .verificationFailed:
            L10n.text("Der vorbereitete Bestand konnte nicht verifiziert werden.")
        }
    }
}

actor BackupRestoreService {
    nonisolated let layout: InventoryStorageLayout

    private let fileManager: FileManager
    private var isPreparing = false
    private var prepared: PreparedRestore?

    init(layout: InventoryStorageLayout = .default, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    func prepare(from source: URL, preferredLanguage: String? = nil) async throws -> BackupRestorePreview {
        guard !isPreparing, prepared == nil else { throw BackupRestoreError.alreadyPreparing }
        try Task.checkCancellation()
        isPreparing = true
        defer { isPreparing = false }

        let liveBeforePreparation = try readLiveState()
        let backupsDirectory = try ensureBackupsDirectory()
        let id = UUID().uuidString
        let stageRoot = backupsDirectory.appendingPathComponent(".Preparing-\(id)", isDirectory: true)
        try fileManager.createDirectory(
            at: stageRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let stageLayout = InventoryStorageLayout(rootURL: stageRoot)
        let stageArchive = stageRoot.appendingPathComponent("Backup.zip")

        do {
            let archiveTask = Task.detached(priority: .userInitiated) {
                try Self.copyArchive(from: source, to: stageArchive)
                try Task.checkCancellation()
                return try BackupArchiveReader().unpack(from: stageArchive, into: stageLayout)
            }
            var snapshot = try await withTaskCancellationHandler {
                try await archiveTask.value
            } onCancel: {
                archiveTask.cancel()
            }
            try Task.checkCancellation()
            try fileManager.removeItem(at: stageArchive)
            if let preferredLanguage {
                snapshot.metadata.preferredLanguage = AppLanguage.normalized(preferredLanguage).rawValue
            }
            let repository = SQLiteInventoryRepository(databaseURL: stageLayout.currentDatabaseURL)
            try await repository.saveSnapshot(snapshot)
            try await repository.verifyIntegrity()
            let verifiedSnapshot = try await repository.loadSnapshot()
            guard snapshot == verifiedSnapshot else { throw BackupRestoreError.verificationFailed }
            try Task.checkCancellation()

            prepared = PreparedRestore(
                snapshot: verifiedSnapshot,
                stageLayout: stageLayout,
                backupDirectory: backupsDirectory.appendingPathComponent("Before-Restore-\(id)", isDirectory: true),
                currentState: liveBeforePreparation
            )
            return BackupRestorePreview(sourceFileName: source.lastPathComponent, counts: verifiedSnapshot.counts)
        } catch {
            try? fileManager.removeItem(at: stageRoot)
            throw error
        }
    }

    func discardPrepared() throws {
        guard let prepared else { return }
        if try Self.stat(at: prepared.stageLayout.rootURL) != nil {
            try fileManager.removeItem(at: prepared.stageLayout.rootURL)
        }
        self.prepared = nil
    }

    func install() throws -> (snapshot: InventorySnapshot, result: BackupRestoreResult) {
        guard let prepared else { throw BackupRestoreError.noPreparedBackup }
        self.prepared = nil
        var stagedRoot = prepared.stageLayout.rootURL
        var keepPreviousBackup = false
        defer {
            if !keepPreviousBackup {
                try? fileManager.removeItem(at: stagedRoot)
            }
        }

        let lock = try lockInstallation()
        defer { close(lock) }
        guard try readLiveState() == prepared.currentState else { throw BackupRestoreError.currentDataChanged }
        try Task.checkCancellation()

        let previousBackupURL: URL?
        if prepared.currentState.directory != nil {
            // The old Current becomes the contents of the permanent backup in
            // the same atomic operation that installs the verified new one.
            try Self.rename(stagedRoot, to: prepared.backupDirectory, flags: UInt32(RENAME_EXCL))
            stagedRoot = prepared.backupDirectory
            let backupLayout = InventoryStorageLayout(rootURL: stagedRoot)
            try Task.checkCancellation()
            try Self.rename(backupLayout.currentDirectoryURL, to: layout.currentDirectoryURL, flags: UInt32(RENAME_SWAP))
            keepPreviousBackup = true
            previousBackupURL = stagedRoot
        } else {
            try Self.rename(prepared.stageLayout.currentDirectoryURL, to: layout.currentDirectoryURL, flags: UInt32(RENAME_EXCL))
            previousBackupURL = nil
        }

        return (
            snapshot: prepared.snapshot,
            result: BackupRestoreResult(counts: prepared.snapshot.counts, previousBackupURL: previousBackupURL)
        )
    }

    private func ensureBackupsDirectory() throws -> URL {
        let directory = layout.rootURL.appendingPathComponent("RestoreBackups", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = try Self.readDirectory(at: directory)
        return directory
    }

    private func lockInstallation() throws -> Int32 {
        let url = layout.rootURL.appendingPathComponent(".RestoreLock")
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.posixFailure() }
        var info = Darwin.stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw BackupRestoreError.unsafeStorageDirectory
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = Self.posixFailure()
            close(descriptor)
            if failure.code == .EWOULDBLOCK {
                throw BackupRestoreError.alreadyPreparing
            }
            throw failure
        }
        return descriptor
    }

    private func readLiveState() throws -> LiveState {
        let current = layout.currentDirectoryURL
        return LiveState(
            directory: try Self.readDirectory(at: current),
            data: try [
                layout.currentDatabaseURL,
                current.appendingPathComponent("inventory.sqlite-wal"),
                layout.currentPhotosDirectoryURL
            ].map { path in
                try Self.stat(at: path).map { FileMarker($0, includeContent: true) }
            }
        )
    }

    private static func readDirectory(at url: URL) throws -> FileMarker? {
        guard let info = try stat(at: url) else { return nil }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw BackupRestoreError.unsafeStorageDirectory }
        return FileMarker(info, includeContent: false)
    }

    private static func stat(at url: URL) throws -> stat? {
        var result = Darwin.stat()
        if lstat(url.path, &result) == 0 {
            return result
        }
        if errno == ENOENT {
            return nil
        }
        throw posixFailure()
    }

    private static func copyArchive(from source: URL, to destination: URL) throws {
        guard source.isFileURL, source.pathExtension.lowercased() == "zip" else {
            throw BackupRestoreError.invalidSource
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw BackupRestoreError.invalidSource }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var before = Darwin.stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG, before.st_size > 0 else {
            throw BackupRestoreError.invalidSource
        }

        let maximumBytes = 500 * 1_024 * 1_024
        guard before.st_size <= maximumBytes else { throw BackupRestoreError.sourceTooLarge }
        let outputDescriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard outputDescriptor >= 0 else { throw posixFailure() }
        let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        defer { try? output.close() }

        var copied = 0
        while let chunk = try input.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= maximumBytes - copied else { throw BackupRestoreError.sourceTooLarge }
            try output.write(contentsOf: chunk)
            copied += chunk.count
        }
        try output.close()
        var after = Darwin.stat()
        guard fstat(descriptor, &after) == 0, copied == after.st_size,
              FileMarker(before, includeContent: true) == FileMarker(after, includeContent: true) else {
            throw BackupRestoreError.sourceChanged
        }
    }

    private static func rename(_ source: URL, to destination: URL, flags: UInt32) throws {
        guard renamex_np(source.path, destination.path, flags) == 0 else {
            throw posixFailure()
        }
    }

    private static func posixFailure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private struct PreparedRestore {
        let snapshot: InventorySnapshot
        let stageLayout: InventoryStorageLayout
        let backupDirectory: URL
        let currentState: LiveState
    }

    private struct LiveState: Equatable {
        let directory: FileMarker?
        let data: [FileMarker?]
    }

    private struct FileMarker: Equatable {
        let device: dev_t
        let inode: ino_t
        let content: [Int64]

        init(_ info: stat, includeContent: Bool) {
            device = info.st_dev
            inode = info.st_ino
            content = includeContent ? [
                info.st_size,
                Int64(info.st_mtimespec.tv_sec),
                Int64(info.st_mtimespec.tv_nsec),
                Int64(info.st_ctimespec.tv_sec),
                Int64(info.st_ctimespec.tv_nsec)
            ] : []
        }
    }
}
