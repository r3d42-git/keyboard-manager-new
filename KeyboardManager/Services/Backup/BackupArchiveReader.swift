import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

enum BackupArchiveReadError: LocalizedError {
    case unsupportedFormat
    case invalidContents
    case invalidImage(String)
    case invalidStage

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: L10n.text("Dieses ZIP ist keine unterstützte Sicherung von Keyboard Manager.")
        case .invalidContents: L10n.text("Die Sicherung ist beschädigt oder enthält widersprüchliche Daten.")
        case let .invalidImage(path): L10n.text("Bilddaten konnten nicht dekodiert werden: %@", arguments: path)
        case .invalidStage: L10n.text("Der Arbeitsordner für die Wiederherstellung ist nicht leer oder nicht verfügbar.")
        }
    }
}

struct BackupArchiveReader: Sendable {
    func unpack(from source: URL, into layout: InventoryStorageLayout) throws -> InventorySnapshot {
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.isFileURL, info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size > 0, size <= BackupExportService.maximumArchiveBytes else {
            throw BackupArchiveReadError.invalidContents
        }
        let archive = try Archive(url: source, accessMode: .read)
        var entries = [String: Entry]()
        var imageBytes: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            guard entry.type == .file, entry.path.utf8.count <= 266, entries[entry.path] == nil,
                  entries.count < 2 * BackupExportService.maximumPhotos + 1 else {
                throw BackupArchiveReadError.invalidContents
            }
            if entry.path == "manifest.json" {
                guard entry.uncompressedSize <= BackupExportService.maximumManifestBytes else {
                    throw BackupExportError.manifestTooLarge
                }
            } else {
                guard entry.uncompressedSize > 0,
                      entry.uncompressedSize <= BackupExportService.maximumPhotoBytes,
                      entry.path.hasPrefix("photos/") || entry.path.hasPrefix("originals/") else {
                    throw BackupArchiveReadError.invalidContents
                }
                imageBytes += entry.uncompressedSize
                guard imageBytes <= BackupExportService.maximumPhotoTotalBytes else {
                    throw BackupExportError.photoDataTooLarge
                }
            }
            entries[entry.path] = entry
        }
        guard let manifestEntry = entries.removeValue(forKey: "manifest.json") else {
            throw BackupArchiveReadError.unsupportedFormat
        }
        let manifest = try decodeManifest(read(manifestEntry, in: archive))
        var snapshot = try manifest.snapshot()
        try BackupExportService.validateInventory(snapshot)
        snapshot.completeOneSidedKeycapMounts()

        let directory = layout.currentPhotosDirectoryURL
        let manager = FileManager.default
        // The caller owns a fresh private stage. Never write into an existing photo library.
        for url in [layout.rootURL, layout.currentDirectoryURL] {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw BackupArchiveReadError.invalidStage
            }
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        guard try manager.contentsOfDirectory(atPath: layout.currentDirectoryURL.path).isEmpty else {
            throw BackupArchiveReadError.invalidStage
        }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            throw BackupArchiveReadError.invalidStage
        }
        do {
            for (definition, photo) in zip(manifest.photos, snapshot.photos) {
                try Task.checkCancellation()
                let data = try imageData(at: definition.file, type: definition.type, entries: &entries, archive: archive)
                let managedData: Data
                if let original = definition.originalFile {
                    managedData = try imageData(at: original, type: PhotoMIMEType.heic.rawValue, entries: &entries, archive: archive)
                } else {
                    managedData = data
                }
                try managedData.write(to: directory.appendingPathComponent(photo.relativeFileName), options: .withoutOverwriting)
            }
            guard entries.isEmpty else { throw BackupArchiveReadError.invalidContents }
            return snapshot
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private func decodeManifest(_ data: Data) throws -> V1ExportManifest {
        guard let manifest = try? JSONDecoder().decode(V1ExportManifest.self, from: data),
              [V1ExportManifest.legacySchemaVersion, V1ExportManifest.currentSchemaVersion].contains(manifest.schemaVersion),
              manifest.format == "keyboard-manager-zip",
              ["en", "de"].contains(manifest.meta.language) else {
            throw BackupArchiveReadError.unsupportedFormat
        }
        if let producer = manifest.producer {
            guard producer == V1ExportManifest.nativeProducer else { throw BackupArchiveReadError.unsupportedFormat }
        } else {
            // Electron used the same schema and note, but serialized insertion-ordered keys using
            // JSON.stringify. Only accept the exact, sorted Foundation representation of old native exports.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard manifest.schemaVersion == V1ExportManifest.legacySchemaVersion,
                  manifest.meta.note == "ZIP-Backup mit Manifest und Bilddateien.",
                  manifest.gallery.showFields == ["manufacturer": true, "format": true, "switches": true, "keycaps": false],
                  manifest.photos.allSatisfy({ $0.originalFile == nil }),
                  try encoder.encode(manifest) == data else {
                throw BackupArchiveReadError.unsupportedFormat
            }
        }
        return manifest
    }

    private func read(_ entry: Entry, in archive: Archive) throws -> Data {
        let expectedSize = Int(entry.uncompressedSize)
        var bytes = Data()
        let crc = try archive.extract(entry) { chunk in
            try Task.checkCancellation()
            guard chunk.count <= expectedSize - bytes.count else { throw BackupArchiveReadError.invalidContents }
            bytes.append(chunk)
        }
        guard bytes.count == expectedSize, crc == entry.checksum else { throw BackupArchiveReadError.invalidContents }
        return bytes
    }

    private func imageData(at path: String, type: String, entries: inout [String: Entry], archive: Archive) throws -> Data {
        guard let entry = entries.removeValue(forKey: path), let mime = PhotoMIMEType(rawValue: type) else {
            throw BackupArchiveReadError.invalidContents
        }
        let bytes = try read(entry, in: archive)
        try Self.validateImage(bytes, as: mime, path: path)
        return bytes
    }

    static func validateImage(_ bytes: Data, as mime: PhotoMIMEType, path: String) throws {
        let types: [UTType]
        switch mime {
        case .jpeg: types = [.jpeg]
        case .png: types = [.png]
        case .gif: types = [.gif]
        case .webP: types = [.webP]
        case .heic: types = [.heic, .heif]
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier),
              types.contains(where: { type.conforms(to: $0) }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 100_000_000 / height,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) != nil else {
            throw BackupArchiveReadError.invalidImage(path)
        }
    }
}

private extension V1ExportManifest {
    func snapshot() throws -> InventorySnapshot {
        try BackupExportService.validateCounts(InventoryCounts(
            boards: boards.count, keycapSets: keycapSets.count, artisanSets: artisanSets.count,
            switchSets: switchSets.count, photos: photos.count
        ))
        var installations = [SwitchInstallation]()
        let switches = try switchSets.map { item in
            guard item.quantity >= 0, item.importRow >= 0, let pins = SwitchPins(rawValue: item.pins),
                  item.mountedBoardId == item.installations.first?.boardId,
                  item.mountedQuantity == item.installations.first?.quantity else {
                throw BackupArchiveReadError.invalidContents
            }
            var available = item.quantity
            for installation in item.installations {
                guard installation.quantity >= 0, installation.quantity <= available else {
                    throw BackupArchiveReadError.invalidContents
                }
                available -= installation.quantity
                installations.append(SwitchInstallation(switchSetID: item.id, boardID: installation.boardId, quantity: installation.quantity))
            }
            return try SwitchSet(
                id: item.id, name: item.name, switchType: item.switchType,
                topHousingMaterial: item.topHousingMaterial, bottomHousingMaterial: item.bottomHousingMaterial,
                stemMaterial: item.stemMaterial, springLength: item.springLength, springType: item.springType,
                preTravel: item.preTravel, totalTravel: item.totalTravel, operatingForce: item.operatingForce,
                bottomOutForce: item.bottomOutForce, pins: pins, hasLEDDiffuser: item.ledDiffuser,
                isFactoryLubed: item.factoryLubed, quantity: item.quantity, importedBoardText: item.importedBoardText,
                importedBoardAllocations: item.importedBoardAllocations.map {
                    ImportedBoardAllocation(boardName: $0.board, quantity: $0.quantity, inferred: $0.inferred)
                },
                importSource: item.importSource, importRow: item.importRow, importKey: item.importKey,
                importWarnings: item.importWarnings, notes: item.notes, photoIDs: item.photoIds,
                mainPhotoID: item.mainPhotoId?.nilIfEmpty, createdAt: date(item.createdAt), updatedAt: date(item.updatedAt)
            )
        }
        let byBoard = Dictionary(grouping: installations, by: \.boardID)
        let restoredBoards = try boards.map { board in
            let keycapIDs: [String]
            if schemaVersion == Self.legacySchemaVersion {
                guard board.keycapSetIds == nil else { throw BackupArchiveReadError.invalidContents }
                keycapIDs = board.keycapSetId?.nilIfEmpty.map { [$0] } ?? []
            } else {
                guard let ids = board.keycapSetIds, board.keycapSetId == ids.first else {
                    throw BackupArchiveReadError.invalidContents
                }
                keycapIDs = ids
            }
            let links = byBoard[board.id] ?? []
            guard board.switchSetIds.count == links.count, board.switchSetQuantities.count == links.count,
                  Set(board.switchSetIds) == Set(links.map(\.switchSetID)), board.switchSetId == board.switchSetIds.first,
                  links.allSatisfy({ board.switchSetQuantities[$0.switchSetID] == $0.quantity }) else {
                throw BackupArchiveReadError.invalidContents
            }
            return try Board(
                id: board.id, name: board.name, manufacturer: board.manufacturer, format: board.format,
                plate: board.plate, pcb: board.pcb, stabilizers: board.stabs, remark: board.remark,
                legacyKeycapsName: board.keycaps, keycapSetIDs: keycapIDs, legacySwitchesName: board.switches,
                photoIDs: board.photoIds, mainPhotoID: board.mainPhotoId?.nilIfEmpty, createdAt: date(board.createdAt), updatedAt: date(board.updatedAt)
            )
        }
        return try InventorySnapshot(
            metadata: AppMetadata(schemaVersion: 1, createdAt: date(meta.createdAt), updatedAt: date(meta.updatedAt), preferredLanguage: meta.language),
            libraryValues: LibraryValues(valuesByKey: lists),
            boards: restoredBoards,
            keycapSets: keycapSets.map { item in
                try KeycapSet(
                    id: item.id, name: item.name, manufacturer: item.manufacturer, profile: item.profile,
                    material: item.material, status: item.status, kits: item.kits, sourceURL: item.sourceUrl,
                    sourceShop: item.sourceShop, mountedBoardID: item.mountedBoardId?.nilIfEmpty, notes: item.notes,
                    photoIDs: item.photoIds, mainPhotoID: item.mainPhotoId?.nilIfEmpty, coverURL: item.coverUrl,
                    externalImageURLs: item.externalImageUrls, trelloCardID: item.trelloCardId, trelloListName: item.trelloListName,
                    createdAt: date(item.createdAt), updatedAt: date(item.updatedAt)
                )
            },
            artisanSets: artisanSets.map { item in
                try ArtisanSet(
                    id: item.id, name: item.name, manufacturer: item.manufacturer, profile: item.profile,
                    material: item.material, status: item.status, tags: item.tags, sourceURL: item.sourceUrl,
                    sourceShop: item.sourceShop, mountedBoardID: item.mountedBoardId?.nilIfEmpty, notes: item.notes,
                    photoIDs: item.photoIds, mainPhotoID: item.mainPhotoId?.nilIfEmpty, coverURL: item.coverUrl,
                    externalImageURLs: item.externalImageUrls, trelloCardID: item.trelloCardId, trelloListName: item.trelloListName,
                    createdAt: date(item.createdAt), updatedAt: date(item.updatedAt)
                )
            },
            switchSets: switches, switchInstallations: installations, photos: photos.map { photo in
                guard let owner = PhotoOwnerType(rawValue: photo.ownerType),
                      photo.boardId == (owner == .board ? photo.ownerId : nil),
                      let mime = PhotoMIMEType(rawValue: photo.type), mime != .heic,
                      photo.file == "photos/\(photo.id).\(mime.fileExtension)" else {
                    throw BackupArchiveReadError.invalidContents
                }
                let restoredMIME: PhotoMIMEType
                if let original = photo.originalFile {
                    guard producer == Self.nativeProducer, mime == .jpeg, original == "originals/\(photo.id).heic" else {
                        throw BackupArchiveReadError.invalidContents
                    }
                    restoredMIME = .heic
                } else {
                    restoredMIME = mime
                }
                return try PhotoRecord(
                    id: photo.id, owner: PhotoOwner(type: owner, id: photo.ownerId), originalName: photo.name,
                    mimeType: restoredMIME, pixelWidth: photo.width, pixelHeight: photo.height,
                    addedAt: date(photo.addedAt), relativeFileName: "\(photo.id).\(restoredMIME.fileExtension)"
                )
            }
        )
    }

    private func date(_ milliseconds: Int64) throws -> Date {
        // Keep timestamp conversion reversible, including when the restored collection is exported again.
        guard (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else {
            throw BackupArchiveReadError.invalidContents
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
}
