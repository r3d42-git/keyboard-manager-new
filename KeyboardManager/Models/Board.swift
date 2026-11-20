import Foundation

struct Board: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var manufacturer: String
    var format: String
    var plate: String
    var pcb: String
    var stabilizers: String
    var remark: String

    // Older collections can retain component names without a linked inventory item.
    var legacyKeycapsName: String
    var keycapSetIDs: [String]
    var legacySwitchesName: String

    var photoIDs: [String]
    var mainPhotoID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        manufacturer: String = "",
        format: String = "",
        plate: String = "",
        pcb: String = "",
        stabilizers: String = "",
        remark: String = "",
        legacyKeycapsName: String = "",
        keycapSetIDs: [String] = [],
        legacySwitchesName: String = "",
        photoIDs: [String] = [],
        mainPhotoID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.format = format
        self.plate = plate
        self.pcb = pcb
        self.stabilizers = stabilizers
        self.remark = remark
        self.legacyKeycapsName = legacyKeycapsName
        self.keycapSetIDs = keycapSetIDs
        self.legacySwitchesName = legacySwitchesName
        self.photoIDs = photoIDs
        self.mainPhotoID = mainPhotoID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case keycapSetID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let keycapSetIDs: [String]
        if values.contains(.keycapSetIDs) {
            keycapSetIDs = try values.decode([String].self, forKey: .keycapSetIDs)
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let id = try legacy.decodeIfPresent(String.self, forKey: .keycapSetID)?.nilIfEmpty
            keycapSetIDs = id.map { [$0] } ?? []
        }
        self.init(
            id: try values.decode(String.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            manufacturer: try values.decode(String.self, forKey: .manufacturer),
            format: try values.decode(String.self, forKey: .format),
            plate: try values.decode(String.self, forKey: .plate),
            pcb: try values.decode(String.self, forKey: .pcb),
            stabilizers: try values.decode(String.self, forKey: .stabilizers),
            remark: try values.decode(String.self, forKey: .remark),
            legacyKeycapsName: try values.decode(String.self, forKey: .legacyKeycapsName),
            keycapSetIDs: keycapSetIDs,
            legacySwitchesName: try values.decode(String.self, forKey: .legacySwitchesName),
            photoIDs: try values.decode([String].self, forKey: .photoIDs),
            mainPhotoID: try values.decodeIfPresent(String.self, forKey: .mainPhotoID),
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            updatedAt: try values.decode(Date.self, forKey: .updatedAt)
        )
    }

    func keycapsSummary(namesByID: [String: String]) -> String {
        let names = keycapSetIDs.compactMap { namesByID[$0] }
        return names.isEmpty ? legacyKeycapsName : names.joined(separator: ", ")
    }

    var hasValidMainPhoto: Bool {
        guard let mainPhotoID else { return true }
        return photoIDs.contains(mainPhotoID)
    }
}
