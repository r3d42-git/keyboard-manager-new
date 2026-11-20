import Foundation
import XCTest
import ZIPFoundation
@testable import KeyboardManager

final class BackupArchiveReaderTests: XCTestCase {
    private var directory: URL!
    private var archiveURL: URL { directory.appendingPathComponent("backup.zip") }
    private var stage: InventoryStorageLayout {
        InventoryStorageLayout(rootURL: directory.appendingPathComponent("restore", isDirectory: true))
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReleasedNativeArchiveRestoresPNGAndOldHEICConversion() throws {
        try historicalZIP.write(to: archiveURL)
        let result = try BackupArchiveReader().unpack(from: archiveURL, into: stage)
        XCTAssertEqual(result.metadata.preferredLanguage, "en")
        XCTAssertEqual(result.boards.first?.name, "Historical board")
        XCTAssertEqual(result.boards.first?.mainPhotoID, "p")
        XCTAssertEqual(result.boards.first?.photoIDs, ["p", "h"])
        let photo = try XCTUnwrap(result.photos.first { $0.id == "h" })
        XCTAssertEqual(photo.originalName, "original.heic")
        XCTAssertEqual(photo.mimeType, .jpeg)
        XCTAssertEqual(photo.relativeFileName, "h.jpg")
        let archived = try entries(in: archiveURL)
        for photo in result.photos {
            let data = try Data(contentsOf: stage.currentPhotosDirectoryURL.appendingPathComponent(photo.relativeFileName))
            XCTAssertEqual(data, archived["photos/" + photo.relativeFileName])
        }
    }

    func testNewExportRoundTripsAllKindsRelationshipsAndBitExactHEIC() async throws {
        try historicalZIP.write(to: archiveURL)
        let source = InventoryStorageLayout(rootURL: directory.appendingPathComponent("source"))
        var snapshot = try BackupArchiveReader().unpack(from: archiveURL, into: source)
        let date = snapshot.metadata.createdAt
        snapshot.libraryValues = .init(valuesByKey: ["manufacturers": ["Öst"]])
        snapshot.boards[0].keycapSetIDs = ["kc_z", "kc"]
        snapshot.keycapSets = [
            .init(id: "kc", name: "Keycaps", kits: ["Base"], mountedBoardID: "b", createdAt: date, updatedAt: date),
            .init(id: "kc_z", name: "Second Keycaps", kits: ["Accent"], mountedBoardID: "b", createdAt: date, updatedAt: date)
        ]
        snapshot.artisanSets = [.init(id: "art", name: "Art", tags: ["Blue"], mountedBoardID: "b", createdAt: date, updatedAt: date)]
        snapshot.switchSets = [.init(id: "sw", name: "Switches", pins: .hallEffect, quantity: 70, importedBoardText: "ref",
                                     importedBoardAllocations: [.init(boardName: "Historical board", quantity: 40, inferred: false)],
                                     importWarnings: ["note"], createdAt: date, updatedAt: date)]
        snapshot.switchInstallations = [.init(switchSetID: "sw", boardID: "b", quantity: 40)]
        let h = try XCTUnwrap(snapshot.photos.firstIndex { $0.id == "h" })
        snapshot.photos[h].mimeType = .heic
        snapshot.photos[h].relativeFileName = "h.heic"
        try originalHEIC.write(to: source.currentPhotosDirectoryURL.appendingPathComponent("h.heic"))
        _ = try await BackupExportService(layout: source).export(snapshot: snapshot, to: archiveURL, exportedAt: date, appVersion: "1.2")
        let packed = try entries(in: archiveURL)
        XCTAssertEqual(packed["originals/h.heic"], originalHEIC)
        XCTAssertNotNil(packed["photos/h.jpg"])
        let restored = try BackupArchiveReader().unpack(from: archiveURL, into: stage)
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(try Data(contentsOf: stage.currentPhotosDirectoryURL.appendingPathComponent("h.heic")), originalHEIC)
    }

    func testSchemaSixRestoresSingularKeycapMountsWithOrWithoutProducer() throws {
        try historicalZIP.write(to: archiveURL)
        var files = try entries(in: archiveURL)
        var manifest = try JSONDecoder().decode(V1ExportManifest.self, from: XCTUnwrap(files["manifest.json"]))
        manifest.keycapSets = [
            .init(
                id: "kc", name: "Keycaps", manufacturer: "", profile: "", material: "", status: "",
                kits: [], sourceUrl: "", sourceShop: "", mountedBoardId: nil, notes: "", photoIds: [],
                mainPhotoId: nil, coverUrl: "", externalImageUrls: [], trelloCardId: "", trelloListName: "",
                createdAt: manifest.meta.createdAt, updatedAt: manifest.meta.updatedAt
            )
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        // The historical exporter could record just one side of the link.
        for producer in [nil, V1ExportManifest.nativeProducer] as [String?] {
            manifest.producer = producer
            manifest.boards[0].keycapSetId = producer == nil ? "kc" : nil
            manifest.keycapSets[0].mountedBoardId = producer == nil ? nil : "b"
            files["manifest.json"] = try encoder.encode(manifest)
            try writeArchive(files)
            let restored = try BackupArchiveReader().unpack(from: archiveURL, into: stage)
            XCTAssertEqual(restored.boards[0].keycapSetIDs, ["kc"])
            XCTAssertEqual(restored.keycapSets[0].mountedBoardID, "b")
            try FileManager.default.removeItem(at: stage.rootURL)
        }
    }

    func testSchemaSevenRejectsMissingOrInconsistentKeycapList() throws {
        try historicalZIP.write(to: archiveURL)
        var files = try entries(in: archiveURL)
        var manifest = try JSONDecoder().decode(V1ExportManifest.self, from: XCTUnwrap(files["manifest.json"]))
        manifest.producer = V1ExportManifest.nativeProducer
        manifest.schemaVersion = 7
        files["manifest.json"] = try JSONEncoder().encode(manifest)
        try assertRejected(files)

        manifest.boards[0].keycapSetIds = []
        manifest.boards[0].keycapSetId = "unlisted"
        files["manifest.json"] = try JSONEncoder().encode(manifest)
        try assertRejected(files)
    }

    func testRejectsDuplicateMissingAndConflictingKeycapMounts() throws {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [
            Board(id: "b", name: "Board", keycapSetIDs: ["kc", "kc"]),
            Board(id: "other", name: "Another Board")
        ]
        snapshot.keycapSets = [KeycapSet(id: "kc", name: "Keycaps")]
        XCTAssertThrowsError(try BackupExportService.validateInventory(snapshot))

        snapshot.boards[0].keycapSetIDs = ["missing"]
        XCTAssertThrowsError(try BackupExportService.validateInventory(snapshot))

        snapshot.boards[0].keycapSetIDs = ["kc"]
        snapshot.boards[1].keycapSetIDs = ["kc"]
        XCTAssertThrowsError(try BackupExportService.validateInventory(snapshot))

        snapshot.boards[1].keycapSetIDs = []
        snapshot.keycapSets[0].mountedBoardID = "other"
        XCTAssertThrowsError(try BackupExportService.validateInventory(snapshot))
    }

    func testRejectsV1FormatOrderAndUnsupportedProducer() throws {
        try historicalZIP.write(to: archiveURL)
        let archived = try entries(in: archiveURL)
        let native = try XCTUnwrap(archived["manifest.json"])
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: native) as? [String: Any])
        // The released Electron exporter starts with schemaVersion and uses JSON.stringify separators.
        let fields = ["schemaVersion", "format", "meta", "lists", "gallery", "boards", "keycapSets", "artisanSets", "switchSets", "photos"]
        let jsFields = try fields.map { key in
            let value = try JSONSerialization.data(withJSONObject: XCTUnwrap(manifest[key]), options: [.fragmentsAllowed])
            return "  \"\(key)\": " + String(decoding: value, as: UTF8.self)
        }
        var changed = archived
        changed["manifest.json"] = Data(("{\n" + jsFields.joined(separator: ",\n") + "\n}").utf8)
        try assertRejected(changed)
        for update in [["producer": "unknown"], ["schemaVersion": 5]] as [[String: Any]] {
            changed["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest.merging(update) { _, new in new })
            try assertRejected(changed)
        }
    }

    func testRefusesUnexpectedPathsAndCorruptPhotoDataAndMaintainsEmptyStage() throws {
        try historicalZIP.write(to: archiveURL)
        let archived = try entries(in: archiveURL)
        var badPath = archived
        badPath["photos/../outside"] = Data([1])
        try assertRejected(badPath)
        var badImage = archived
        badImage["photos/p.png"] = Data("invalid".utf8)
        try assertRejected(badImage)
        badImage["photos/p.png"] = archived["photos/h.jpg"]
        try assertRejected(badImage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.currentPhotosDirectoryURL.path))

        var wrongOwner = archived
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(archived["manifest.json"])) as? [String: Any])
        manifest["producer"] = V1ExportManifest.nativeProducer
        var photos = try XCTUnwrap(manifest["photos"] as? [[String: Any]])
        photos[0]["ownerId"] = "missing"
        manifest["photos"] = photos
        wrongOwner["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        try assertRejected(wrongOwner)
    }

    func testRefusesDuplicateEntriesAndCorruptCRC() throws {
        try historicalZIP.write(to: archiveURL)
        let archived = try entries(in: archiveURL)
        try FileManager.default.removeItem(at: archiveURL)
        do {
            let zip = try Archive(url: archiveURL, accessMode: .create)
            for (path, bytes) in archived { try add(path, bytes, to: zip) }
            try add("manifest.json", XCTUnwrap(archived["manifest.json"]), to: zip)
        }
        XCTAssertThrowsError(try BackupArchiveReader().unpack(from: archiveURL, into: stage))
        var corrupt = historicalZIP
        let signature = try XCTUnwrap(corrupt.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        corrupt[signature.lowerBound + 16] ^= 1
        try corrupt.write(to: archiveURL)
        XCTAssertThrowsError(try BackupArchiveReader().unpack(from: archiveURL, into: stage))
    }

    func testRejectsOversizedManifestAndInvalidStock() throws {
        try historicalZIP.write(to: archiveURL)
        let archived = try entries(in: archiveURL)
        try assertRejected(["manifest.json": Data(repeating: 32, count: BackupExportService.maximumManifestBytes + 1)])
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "b", name: "Board")]
        snapshot.switchSets = [SwitchSet(id: "s", name: "Switch", quantity: 10)]
        snapshot.switchInstallations = [SwitchInstallation(switchSetID: "s", boardID: "b", quantity: 11)]
        XCTAssertThrowsError(try BackupExportService.validateInventory(snapshot))
        var invalid = archived
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(archived["manifest.json"])) as? [String: Any])
        var boards = try XCTUnwrap(manifest["boards"] as? [[String: Any]])
        boards[0]["switchSetIds"] = ["missing"]
        manifest["boards"] = boards
        manifest["producer"] = V1ExportManifest.nativeProducer
        invalid["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        try assertRejected(invalid)
    }

    func testExistingPhotoDirectoryIsNeverModified() throws {
        try historicalZIP.write(to: archiveURL)
        try FileManager.default.createDirectory(at: stage.currentPhotosDirectoryURL, withIntermediateDirectories: true)
        let existing = stage.currentPhotosDirectoryURL.appendingPathComponent("p.png")
        let sentinel = Data("existing photo".utf8)
        try sentinel.write(to: existing)
        XCTAssertThrowsError(try BackupArchiveReader().unpack(from: archiveURL, into: stage))
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stage.currentPhotosDirectoryURL.path), ["p.png"])
    }

    private func assertRejected(_ files: [String: Data], line: UInt = #line) throws {
        try writeArchive(files)
        XCTAssertThrowsError(try BackupArchiveReader().unpack(from: archiveURL, into: stage), line: line)
    }

    private func writeArchive(_ files: [String: Data]) throws {
        try FileManager.default.removeItem(at: archiveURL)
        let zip = try Archive(url: archiveURL, accessMode: .create)
        for (path, bytes) in files { try add(path, bytes, to: zip) }
    }

    private func add(_ path: String, _ data: Data, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, length in
            data.subdata(in: Int(position)..<(Int(position) + length))
        }
    }

    private func entries(in url: URL) throws -> [String: Data] {
        let zip = try Archive(url: url, accessMode: .read)
        var files: [String: Data] = [:]
        for entry in zip {
            var bytes = Data()
            _ = try zip.extract(entry) { bytes.append($0) }
            files[entry.path] = bytes
        }
        return files
    }
    // Fixed synthetic ZIP produced by the unmodified v1.1.2 native exporter, including its CRCs and JPEG copy.
    private var historicalZIP: Data {
        Data(base64Encoded: """
        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
        AAADAAMArwAAACcFAAAAAA==
        """, options: .ignoreUnknownCharacters)!
    }
    private var originalHEIC: Data {
        Data(base64Encoded: """
        AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAABhm1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAA
        AAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAAAjaWluZgAAAAAAAQAAABVp
        bmZlAgAAAAABAABodmMxAAAAAOZpcHJwAAAAxWlwY28AAAATY29scm5jbHgAAgACAAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAA
        AAAAEAAAABAAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAAcWh2Y0MBA3AAAACwAAAAAAAe8AD8/fj4AAALA6AAAQAXQAEMAf//
        A3AAAAMAsAAAAwAAAwAecCShAAEAI0IBAQNwAAADALAAAAMAAAMAHqAUIEHAkwziHuRZVNwICBgCogABAAlEAcBhcshEU2QAAAAZ
        aXBtYQAAAAAAAAABAAEGgQIDBYaEAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAAboAAAA9AAAAAW1kYXQAAAAAAAAATQAAADkoAa+i
        9kaBfP/7rl6/32v//iPL1X/2cf/+mQZ/yFj3TLJn+iD5wjm69n+kpO+lKCL2FfgrcISbIrg=
        """, options: .ignoreUnknownCharacters)!
    }
}
