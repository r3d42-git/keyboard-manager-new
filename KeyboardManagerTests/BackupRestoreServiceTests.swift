import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import KeyboardManager

@MainActor
final class BackupRestoreServiceTests: XCTestCase {
    func testInstallsVerifiedCopyAndRetainsPreviousCurrentWithItsPhotos() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = BackupRestoreService(layout: fixture.liveLayout)
        let oldDatabase = try Data(contentsOf: fixture.liveLayout.currentDatabaseURL)

        let preview = try await service.prepare(from: fixture.archive)
        XCTAssertEqual(preview.sourceFileName, fixture.archive.lastPathComponent)
        XCTAssertEqual(preview.counts, fixture.incoming.counts)
        XCTAssertEqual(try Data(contentsOf: fixture.liveLayout.currentDatabaseURL), oldDatabase)
        XCTAssertEqual(try photoData(in: fixture.liveLayout), fixture.previousPhoto)

        // The approved preview stays tied to its staged contents even when
        // the selected ZIP path changes before the user confirms.
        try Data("changed source".utf8).write(to: fixture.archive, options: .atomic)
        let installation = try await service.install()
        let previousBackup = try XCTUnwrap(installation.result.previousBackupURL)
        let previousLayout = InventoryStorageLayout(rootURL: previousBackup)
        let previousRepository = SQLiteInventoryRepository(databaseURL: previousLayout.currentDatabaseURL)
        let archived = try await previousRepository.loadSnapshot()
        let installed = try await fixture.liveRepository.loadSnapshot()
        try await fixture.liveRepository.verifyIntegrity()

        XCTAssertEqual(archived, fixture.previous)
        XCTAssertEqual(try photoData(in: previousLayout), fixture.previousPhoto)
        XCTAssertEqual(installation.snapshot, installed)
        XCTAssertEqual(installed, fixture.incoming)
        XCTAssertEqual(try photoData(in: fixture.liveLayout), fixture.incomingPhoto)
    }

    func testCancelDiscardsPreparedFilesAndDuplicatePreparationIsRejected() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = BackupRestoreService(layout: fixture.liveLayout)
        _ = try await service.prepare(from: fixture.archive)

        do {
            _ = try await service.prepare(from: fixture.archive)
            XCTFail("A restore was already prepared.")
        } catch BackupRestoreError.alreadyPreparing {}

        try await service.discardPrepared()
        do {
            _ = try await service.install()
            XCTFail("A cancelled restore must be discarded.")
        } catch BackupRestoreError.noPreparedBackup {}

        let live = try await fixture.liveRepository.loadSnapshot()
        XCTAssertEqual(live, fixture.previous)
        XCTAssertEqual(try photoData(in: fixture.liveLayout), fixture.previousPhoto)
        XCTAssertTrue(try backupDirectories(in: fixture.liveLayout).isEmpty)
    }

    func testMalformedArchiveLeavesCurrentAndNoPendingStage() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("malformed ZIP".utf8).write(to: fixture.archive)
        let service = BackupRestoreService(layout: fixture.liveLayout)

        do {
            _ = try await service.prepare(from: fixture.archive)
            XCTFail("A malformed backup should fail preparation.")
        } catch {}

        let live = try await fixture.liveRepository.loadSnapshot()
        XCTAssertEqual(live, fixture.previous)
        XCTAssertEqual(try photoData(in: fixture.liveLayout), fixture.previousPhoto)
        XCTAssertTrue(try backupDirectories(in: fixture.liveLayout).isEmpty)
    }

    func testCurrentChangedAfterPreviewRejectsReplacement() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = BackupRestoreService(layout: fixture.liveLayout)
        _ = try await service.prepare(from: fixture.archive)
        var changed = fixture.previous
        changed.boards[0].name = "Updated after preview"
        try await fixture.liveRepository.saveSnapshot(changed)

        do {
            _ = try await service.install()
            XCTFail("A stale preview may not replace the changed inventory.")
        } catch BackupRestoreError.currentDataChanged {}

        let live = try await fixture.liveRepository.loadSnapshot()
        XCTAssertEqual(live, changed)
        XCTAssertEqual(try photoData(in: fixture.liveLayout), fixture.previousPhoto)
        XCTAssertTrue(try backupDirectories(in: fixture.liveLayout).isEmpty)
    }

    func testRestoreIntoEmptyLayoutDoesNotCreatePriorBackup() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let emptyLayout = InventoryStorageLayout(rootURL: fixture.directory.appendingPathComponent("Empty"))
        let service = BackupRestoreService(layout: emptyLayout)
        _ = try await service.prepare(from: fixture.archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyLayout.currentDirectoryURL.path))

        let installation = try await service.install()
        XCTAssertNil(installation.result.previousBackupURL)
        XCTAssertEqual(try photoData(in: emptyLayout), fixture.incomingPhoto)
        XCTAssertTrue(try backupDirectories(in: emptyLayout).isEmpty)
    }

    func testStoreProtectsDirtyDraftAndCancelKeepsCleanEditor() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = makeStore(fixture)
        await store.load()
        store.editItem(kind: .board, id: "board_1")
        let editor = store.editorIdentity

        store.requestBackupRestore()
        XCTAssertTrue(store.isBackupRestorePresented)
        XCTAssertTrue(store.isBackupRestoreActive)
        await store.prepareBackupRestore(from: fixture.archive)
        await store.cancelBackupRestore()
        XCTAssertFalse(store.isBackupRestoreActive)
        XCTAssertEqual(store.route, .capture)
        XCTAssertEqual(store.editorIdentity, editor)

        store.isEditorDirty = true
        store.requestBackupRestore()
        XCTAssertTrue(store.isDiscardConfirmationPresented)
        XCTAssertFalse(store.isBackupRestorePresented)
        store.cancelDiscard()
        XCTAssertTrue(store.isEditorDirty)
        XCTAssertEqual(store.editorIdentity, editor)

        store.requestBackupRestore()
        store.confirmDiscardAndContinue()
        XCTAssertFalse(store.isEditorDirty)
        XCTAssertEqual(store.route, .overview)
        XCTAssertTrue(store.isBackupRestorePresented)
        await store.cancelBackupRestore()
    }

    func testStoreBlocksWritesUntilRestoreClosesAndRefreshesReusedPhotoID() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = makeStore(fixture)
        await store.load()
        store.collectionSort = .recentlyUpdated
        store.selectedKind = .switchSet
        var filters = InventoryFilters()
        filters.searchText = "will not match restored data"
        store.overviewFiltersByKind[.board] = filters
        store.backupExportState = .failed("old backup status")
        store.reportExportState = .failed("old report status")
        let oldThumbnail = await store.thumbnailData(for: fixture.previous.photos[0])
        XCTAssertNotNil(oldThumbnail)

        store.requestBackupRestore()
        await store.prepareBackupRestore(from: fixture.archive)
        guard case .ready = store.backupRestoreState else {
            return XCTFail("Expected backup preview. State: \(store.backupRestoreState)")
        }
        XCTAssertFalse(store.canStartEditor)
        XCTAssertFalse(store.canExportBackup)
        XCTAssertFalse(store.canExportReport)
        store.requestRoute(.gallery)
        let deleted = await store.deleteItem(kind: .board, id: "board_1")
        await store.updatePreferredLanguage("en")
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.route, .gallery)
        XCTAssertEqual(store.snapshot, fixture.previous)
        XCTAssertEqual(store.backupRestoreRevision, 0)

        await store.installBackupRestore()
        guard case .succeeded = store.backupRestoreState else {
            return XCTFail("Expected installed backup. State: \(store.backupRestoreState)")
        }
        XCTAssertEqual(store.backupRestoreRevision, 1)
        XCTAssertEqual(store.snapshot.metadata.preferredLanguage, "de")
        XCTAssertEqual(store.snapshot.boards.map(\.name), ["Restored"])
        XCTAssertEqual(store.selectedKind, .board)
        XCTAssertTrue(store.overviewFiltersByKind.isEmpty)
        XCTAssertEqual(store.overviewSortsByKind[.board], .recentlyUpdated)
        XCTAssertEqual(store.backupExportState, .idle)
        XCTAssertEqual(store.reportExportState, .idle)
        let newRecord = try XCTUnwrap(store.photoRecord(id: "photo_1"))
        let restoredThumbnail = await store.thumbnailData(for: newRecord)
        XCTAssertNotNil(restoredThumbnail)
        XCTAssertNotEqual(restoredThumbnail, oldThumbnail)
        await store.cancelBackupRestore()
        XCTAssertFalse(store.isBackupRestoreActive)
        XCTAssertTrue(store.canExportBackup)
    }

    private func makeStore(_ fixture: Fixture) -> InventoryStore {
        InventoryStore(
            repository: fixture.liveRepository,
            backupExportService: BackupExportService(layout: fixture.liveLayout),
            backupRestoreService: BackupRestoreService(layout: fixture.liveLayout),
            photoService: PhotoImportService(layout: fixture.liveLayout),
            thumbnailService: ThumbnailService(layout: fixture.liveLayout)
        )
    }

    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardManagerRestoreTests-\(UUID().uuidString)", isDirectory: true)
        let liveLayout = InventoryStorageLayout(rootURL: directory.appendingPathComponent("Live"))
        let sourceLayout = InventoryStorageLayout(rootURL: directory.appendingPathComponent("Source"))
        let liveRepository = SQLiteInventoryRepository(databaseURL: liveLayout.currentDatabaseURL)
        let oldPhoto = try makePNG(red: 1, blue: 0)
        let newPhoto = try makePNG(red: 0, blue: 1)
        let previous = makeSnapshot(name: "Previous", language: "de")
        var incoming = makeSnapshot(name: "Restored", language: "en")
        let date = incoming.metadata.createdAt
        incoming.boards[0].keycapSetIDs = ["keycap_2", "keycap_1"]
        incoming.keycapSets = [
            KeycapSet(id: "keycap_1", name: "Base", mountedBoardID: "board_1", createdAt: date, updatedAt: date),
            KeycapSet(id: "keycap_2", name: "Accent", mountedBoardID: "board_1", createdAt: date, updatedAt: date)
        ]
        let archive = directory.appendingPathComponent("Keyboard Backup.zip")

        do {
            try writePhoto(oldPhoto, in: liveLayout)
            try await liveRepository.saveSnapshot(previous)
            try writePhoto(newPhoto, in: sourceLayout)
            _ = try await BackupExportService(layout: sourceLayout).export(
                snapshot: incoming,
                to: archive,
                exportedAt: incoming.metadata.updatedAt,
                appVersion: "1.0-test"
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        return Fixture(
            directory: directory,
            liveLayout: liveLayout,
            liveRepository: liveRepository,
            previous: previous,
            incoming: incoming,
            archive: archive,
            previousPhoto: oldPhoto,
            incomingPhoto: newPhoto
        )
    }

    private func makeSnapshot(name: String, language: String) -> InventorySnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = InventorySnapshot.empty
        snapshot.metadata = AppMetadata(schemaVersion: 1, createdAt: date, updatedAt: date, preferredLanguage: language)
        snapshot.boards = [
            Board(id: "board_1", name: name, photoIDs: ["photo_1"], mainPhotoID: "photo_1", createdAt: date, updatedAt: date)
        ]
        snapshot.photos = [
            PhotoRecord(
                id: "photo_1",
                owner: PhotoOwner(type: .board, id: "board_1"),
                originalName: "photo.png",
                mimeType: .png,
                pixelWidth: 2,
                pixelHeight: 2,
                addedAt: date,
                relativeFileName: "photo_1.png"
            )
        ]
        return snapshot
    }

    private func writePhoto(_ data: Data, in layout: InventoryStorageLayout) throws {
        try FileManager.default.createDirectory(at: layout.currentPhotosDirectoryURL, withIntermediateDirectories: true)
        try data.write(to: layout.currentPhotosDirectoryURL.appendingPathComponent("photo_1.png"))
    }

    private func photoData(in layout: InventoryStorageLayout) throws -> Data {
        try Data(contentsOf: layout.currentPhotosDirectoryURL.appendingPathComponent("photo_1.png"))
    }

    private func backupDirectories(in layout: InventoryStorageLayout) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: layout.rootURL.appendingPathComponent("RestoreBackups"),
            includingPropertiesForKeys: nil
        )
    }

    private func makePNG(red: CGFloat, blue: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private struct Fixture {
        let directory: URL
        let liveLayout: InventoryStorageLayout
        let liveRepository: SQLiteInventoryRepository
        let previous: InventorySnapshot
        let incoming: InventorySnapshot
        let archive: URL
        let previousPhoto: Data
        let incomingPhoto: Data
    }
}
