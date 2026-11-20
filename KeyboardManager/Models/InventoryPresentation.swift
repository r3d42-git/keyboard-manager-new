import Foundation

struct InventoryMetadataValue: Hashable, Sendable {
    var label: String
    var value: String
    var relationshipKind: InventoryItemKind?
}

struct InventoryItemSummary: Identifiable, Hashable, Sendable {
    var id: String
    var kind: InventoryItemKind
    var name: String
    var manufacturer: String
    var primaryDetail: String
    var secondaryDetail: String
    var format: String
    var profile: String
    var status: String
    var switchType: String
    var operatingForce: String
    var pins: SwitchPins?
    var quantity: Int?
    var installedQuantity: Int?
    var availableQuantity: Int?
    var mountedBoardID: String?
    var mountedBoardSummary: String
    var keycapsSummary: String
    var switchesSummary: String
    var contentsSummary: String
    var notes: String
    var sourceURL: String
    var photoIDs: [String]
    var mainPhotoID: String?
    var externalImageURLs: [String]
    var metadata: [InventoryMetadataValue]
    var updatedAt: Date

    var photoCount: Int { photoIDs.count }
    var externalImageCount: Int { externalImageURLs.count }
    var stockSummary: String {
        guard let quantity, let installedQuantity, let availableQuantity else { return "" }
        return "\(quantity) / \(installedQuantity) / \(availableQuantity)"
    }

    var searchableText: String {
        (
            [
                name,
                manufacturer,
                primaryDetail,
                secondaryDetail,
                stockSummary,
                mountedBoardSummary,
                keycapsSummary,
                switchesSummary,
                contentsSummary,
                notes
            ]
                + metadata.flatMap { [$0.label, $0.value] }
        )
        .joined(separator: " ")
    }
}

struct InventoryFilters: Equatable, Sendable {
    var searchText = ""
    var manufacturer = ""
    var format = ""
    var profile = ""
    var status = ""
    var switchType = ""
    var operatingForce = ""
    var pins: SwitchPins?
    var withoutPhoto = false
    var unmountedOnly = false

    func isEmpty(for kind: InventoryItemKind) -> Bool {
        guard searchText.isEmpty, !withoutPhoto else { return false }
        switch kind {
        case .board:
            return manufacturer.isEmpty && format.isEmpty
        case .keycapSet, .artisanSet:
            return manufacturer.isEmpty && profile.isEmpty && status.isEmpty && !unmountedOnly
        case .switchSet:
            return switchType.isEmpty && operatingForce.isEmpty && pins == nil
        }
    }
}

struct InventorySort: SortComparator {
    enum Field: String, Sendable {
        case name, manufacturer, primaryDetail, switches, keycaps, contents, mountedBoard
        case quantity, installedQuantity, availableQuantity, operatingForce, photoCount, updatedAt

        func title(for kind: InventoryItemKind) -> String {
            switch self {
            case .name: L10n.text("Name")
            case .manufacturer: L10n.text("Hersteller")
            case .primaryDetail:
                switch kind {
                case .board: L10n.text("Format")
                case .keycapSet, .artisanSet: L10n.text("Profil")
                case .switchSet: L10n.text("Typ")
                }
            case .switches: L10n.text("Switches")
            case .keycaps: L10n.text("Keycaps")
            case .contents: kind == .artisanSet ? L10n.text("Tags") : L10n.text("Kits")
            case .mountedBoard: L10n.text("Board")
            case .quantity: L10n.text("Gesamt")
            case .installedQuantity: L10n.text("Verbaut")
            case .availableQuantity: L10n.text("Verfügbar")
            case .operatingForce: L10n.text("Betätigungskraft")
            case .photoCount: L10n.text("Fotos")
            case .updatedAt: L10n.text("Zuletzt geändert")
            }
        }

        static func available(for kind: InventoryItemKind) -> [Self] {
            switch kind {
            case .board: [.name, .manufacturer, .primaryDetail, .switches, .keycaps, .photoCount, .updatedAt]
            case .keycapSet, .artisanSet: [.name, .manufacturer, .primaryDetail, .contents, .mountedBoard, .photoCount, .updatedAt]
            case .switchSet: [.name, .primaryDetail, .quantity, .installedQuantity, .availableQuantity, .mountedBoard, .operatingForce, .photoCount, .updatedAt]
            }
        }
    }

    var field: Field
    var order: SortOrder

    init(_ field: Field, order: SortOrder = .forward) {
        self.field = field
        self.order = order
    }

    static let name = InventorySort(.name)
    static let recentlyUpdated = InventorySort(.updatedAt, order: .reverse)

    static func saved(for kind: InventoryItemKind, in preferences: UserDefaults) -> Self? {
        guard let entry = preferences.dictionary(forKey: preferenceKey(for: kind)),
              let fieldName = entry["field"] as? String, let field = Field(rawValue: fieldName),
              Field.available(for: kind).contains(field),
              let ascending = entry["ascending"] as? Bool else { return nil }
        return Self(field, order: ascending ? .forward : .reverse)
    }

    func save(for kind: InventoryItemKind, in preferences: UserDefaults) {
        preferences.set(["field": field.rawValue, "ascending": order == .forward],
                        forKey: Self.preferenceKey(for: kind))
    }

    private static func preferenceKey(for kind: InventoryItemKind) -> String {
        "collectionSort.\(kind.rawValue)"
    }

    func compare(_ lhs: InventoryItemSummary, _ rhs: InventoryItemSummary) -> ComparisonResult {
        let (left, right) = order == .forward ? (lhs, rhs) : (rhs, lhs)
        switch field {
        case .name:
            let result = left.name.localizedStandardCompare(right.name)
            return result == .orderedSame ? left.id.compare(right.id) : result
        case .manufacturer: return left.manufacturer.localizedStandardCompare(right.manufacturer)
        case .primaryDetail: return left.primaryDetail.localizedStandardCompare(right.primaryDetail)
        case .switches: return left.switchesSummary.localizedStandardCompare(right.switchesSummary)
        case .keycaps: return left.keycapsSummary.localizedStandardCompare(right.keycapsSummary)
        case .contents: return left.contentsSummary.localizedStandardCompare(right.contentsSummary)
        case .mountedBoard: return left.mountedBoardSummary.localizedStandardCompare(right.mountedBoardSummary)
        case .quantity: return ComparableComparator<Int>().compare(left.quantity ?? 0, right.quantity ?? 0)
        case .installedQuantity: return ComparableComparator<Int>().compare(left.installedQuantity ?? 0, right.installedQuantity ?? 0)
        case .availableQuantity: return ComparableComparator<Int>().compare(left.availableQuantity ?? 0, right.availableQuantity ?? 0)
        case .operatingForce: return left.operatingForce.localizedStandardCompare(right.operatingForce)
        case .photoCount: return ComparableComparator<Int>().compare(left.photoCount, right.photoCount)
        case .updatedAt: return left.updatedAt.compare(right.updatedAt)
        }
    }
}

enum InventoryQuery {
    static let galleryKinds: [InventoryItemKind] = [.board, .keycapSet, .artisanSet]

    static func items(in snapshot: InventorySnapshot, kind: InventoryItemKind) -> [InventoryItemSummary] {
        switch kind {
        case .board:
            let namesByID = Dictionary(uniqueKeysWithValues: snapshot.keycapSets.map { ($0.id, $0.name) })
            return snapshot.boards.map { board in
                let keycaps = board.keycapsSummary(namesByID: namesByID)
                let switchInstallations = snapshot.switchInstallations
                    .filter { $0.boardID == board.id }
                let resolvedSwitches = switchInstallations.compactMap { installation in
                    guard let switchSet = snapshot.switchSets.first(
                        where: { $0.id == installation.switchSetID }
                    ) else {
                        return nil
                    }
                    return L10n.text(
                        "%@ · %lld Stück",
                        arguments: switchSet.name,
                        installation.quantity
                    )
                }
                .joined(separator: ", ")
                let switches = resolvedSwitches.isEmpty
                    ? board.legacySwitchesName
                    : resolvedSwitches
                return InventoryItemSummary(
                    id: board.id,
                    kind: .board,
                    name: board.name,
                    manufacturer: board.manufacturer,
                    primaryDetail: board.format,
                    secondaryDetail: [board.pcb, board.plate].filter { !$0.isEmpty }.joined(separator: " · "),
                    format: board.format,
                    profile: "",
                    status: "",
                    switchType: "",
                    operatingForce: "",
                    pins: nil,
                    quantity: nil,
                    mountedBoardSummary: "",
                    keycapsSummary: keycaps,
                    switchesSummary: switches,
                    contentsSummary: "",
                    notes: board.remark,
                    sourceURL: "",
                    photoIDs: board.photoIDs,
                    mainPhotoID: board.mainPhotoID,
                    externalImageURLs: [],
                    metadata: [
                        .init(label: L10n.text("Hersteller"), value: board.manufacturer),
                        .init(label: L10n.text("Format"), value: board.format),
                        .init(label: "PCB", value: board.pcb),
                        .init(label: "Plate", value: board.plate),
                        .init(label: L10n.text("Stabilisatoren"), value: board.stabilizers),
                        .init(label: L10n.text("Keycaps"), value: keycaps, relationshipKind: .keycapSet),
                        .init(label: L10n.text("Switches"), value: switches, relationshipKind: .switchSet)
                    ],
                    updatedAt: board.updatedAt
                )
            }
        case .keycapSet:
            return snapshot.keycapSets.map { keycapSet in
                let mountedBoard = keycapSet.mountedBoardID
                    .flatMap { boardID in
                        snapshot.boards.first(where: { $0.id == boardID })?.name
                    }
                    ?? ""
                return InventoryItemSummary(
                    id: keycapSet.id,
                    kind: .keycapSet,
                    name: keycapSet.name,
                    manufacturer: keycapSet.manufacturer,
                    primaryDetail: keycapSet.profile,
                    secondaryDetail: keycapSet.status,
                    format: "",
                    profile: keycapSet.profile,
                    status: keycapSet.status,
                    switchType: "",
                    operatingForce: "",
                    pins: nil,
                    quantity: nil,
                    mountedBoardID: keycapSet.mountedBoardID?.nilIfEmpty,
                    mountedBoardSummary: mountedBoard,
                    keycapsSummary: "",
                    switchesSummary: "",
                    contentsSummary: keycapSet.kits.joined(separator: ", "),
                    notes: keycapSet.notes,
                    sourceURL: keycapSet.sourceURL,
                    photoIDs: keycapSet.photoIDs,
                    mainPhotoID: keycapSet.mainPhotoID,
                    externalImageURLs: uniqueExternalImageURLs(
                        coverURL: keycapSet.coverURL,
                        additionalURLs: keycapSet.externalImageURLs
                    ),
                    metadata: [
                        .init(label: L10n.text("Hersteller"), value: keycapSet.manufacturer),
                        .init(label: L10n.text("Profil"), value: keycapSet.profile),
                        .init(label: L10n.text("Material"), value: keycapSet.material),
                        .init(label: L10n.text("Status"), value: keycapSet.status),
                        .init(label: "Kits", value: keycapSet.kits.joined(separator: ", ")),
                        .init(label: L10n.text("Board"), value: mountedBoard),
                        .init(label: L10n.text("Shop"), value: keycapSet.sourceShop)
                    ],
                    updatedAt: keycapSet.updatedAt
                )
            }
        case .artisanSet:
            return snapshot.artisanSets.map { artisanSet in
                let mountedBoard = artisanSet.mountedBoardID
                    .flatMap { boardID in
                        snapshot.boards.first(where: { $0.id == boardID })?.name
                    }
                    ?? ""
                return InventoryItemSummary(
                    id: artisanSet.id,
                    kind: .artisanSet,
                    name: artisanSet.name,
                    manufacturer: artisanSet.manufacturer,
                    primaryDetail: artisanSet.profile,
                    secondaryDetail: artisanSet.status,
                    format: "",
                    profile: artisanSet.profile,
                    status: artisanSet.status,
                    switchType: "",
                    operatingForce: "",
                    pins: nil,
                    quantity: nil,
                    mountedBoardID: artisanSet.mountedBoardID?.nilIfEmpty,
                    mountedBoardSummary: mountedBoard,
                    keycapsSummary: "",
                    switchesSummary: "",
                    contentsSummary: artisanSet.tags.joined(separator: ", "),
                    notes: artisanSet.notes,
                    sourceURL: artisanSet.sourceURL,
                    photoIDs: artisanSet.photoIDs,
                    mainPhotoID: artisanSet.mainPhotoID,
                    externalImageURLs: uniqueExternalImageURLs(
                        coverURL: artisanSet.coverURL,
                        additionalURLs: artisanSet.externalImageURLs
                    ),
                    metadata: [
                        .init(label: L10n.text("Hersteller"), value: artisanSet.manufacturer),
                        .init(label: L10n.text("Profil"), value: artisanSet.profile),
                        .init(label: L10n.text("Material"), value: artisanSet.material),
                        .init(label: L10n.text("Status"), value: artisanSet.status),
                        .init(label: "Tags", value: artisanSet.tags.joined(separator: ", ")),
                        .init(label: L10n.text("Board"), value: mountedBoard),
                        .init(label: L10n.text("Shop"), value: artisanSet.sourceShop)
                    ],
                    updatedAt: artisanSet.updatedAt
                )
            }
        case .switchSet:
            return snapshot.switchSets.map { switchSet in
                let installed = switchSet.installedQuantity(in: snapshot.switchInstallations)
                let available = switchSet.availableQuantity(in: snapshot.switchInstallations)
                let mountedBoards = snapshot.switchInstallations
                    .filter { $0.switchSetID == switchSet.id }
                    .compactMap { installation -> (name: String, quantity: Int)? in
                        guard let board = snapshot.boards.first(
                                where: { $0.id == installation.boardID }
                              ) else {
                            return nil
                        }
                        return (board.name, installation.quantity)
                    }
                    .sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    .map {
                        $0.quantity > 0
                            ? "\($0.name) (\($0.quantity))"
                            : $0.name
                    }
                    .joined(separator: ", ")
                return InventoryItemSummary(
                    id: switchSet.id,
                    kind: .switchSet,
                    name: switchSet.name,
                    manufacturer: "",
                    primaryDetail: switchSet.switchType,
                    secondaryDetail: switchSet.pins.displayName,
                    format: "",
                    profile: "",
                    status: "",
                    switchType: switchSet.switchType,
                    operatingForce: switchSet.operatingForce,
                    pins: switchSet.pins,
                    quantity: switchSet.quantity,
                    installedQuantity: installed,
                    availableQuantity: available,
                    mountedBoardSummary: mountedBoards,
                    keycapsSummary: "",
                    switchesSummary: "",
                    contentsSummary: "",
                    notes: switchSet.notes,
                    sourceURL: "",
                    photoIDs: switchSet.photoIDs,
                    mainPhotoID: switchSet.mainPhotoID,
                    externalImageURLs: [],
                    metadata: [
                        .init(label: L10n.text("Typ"), value: switchSet.switchType),
                        .init(label: L10n.text("Pins"), value: switchSet.pins.displayName),
                        .init(label: L10n.text("Betätigungskraft"), value: switchSet.operatingForce),
                        .init(label: "Bottom-out", value: switchSet.bottomOutForce),
                        .init(label: L10n.text("Gesamt"), value: "\(switchSet.quantity)"),
                        .init(label: L10n.text("Verbaut"), value: "\(installed)"),
                        .init(label: L10n.text("Verfügbar"), value: "\(available)"),
                        .init(label: L10n.text("Board"), value: mountedBoards)
                    ],
                    updatedAt: switchSet.updatedAt
                )
            }
        }
    }

    static func results(
        in snapshot: InventorySnapshot,
        kind: InventoryItemKind,
        filters: InventoryFilters,
        sort: InventorySort
    ) -> [InventoryItemSummary] {
        items(in: snapshot, kind: kind)
            .filter { item in
                matchesSearch(item, searchText: filters.searchText)
                    && matchesExact(item.manufacturer, filters.manufacturer)
                    && matchesExact(item.format, filters.format)
                    && matchesExact(item.profile, filters.profile)
                    && matchesExact(item.status, filters.status)
                    && matchesExact(item.switchType, filters.switchType)
                    && matchesExact(item.operatingForce, filters.operatingForce)
                    && (filters.pins == nil || item.pins == filters.pins)
                    && (!filters.withoutPhoto || item.photoIDs.isEmpty)
                    && (!filters.unmountedOnly || !kind.supportsMountFilter || item.mountedBoardID == nil)
            }
            .sorted(using: [sort, .name])
    }

    private static func uniqueExternalImageURLs(
        coverURL: String,
        additionalURLs: [String]
    ) -> [String] {
        var seen = Set<String>()
        return ([coverURL] + additionalURLs).filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }

    static func values(
        _ keyPath: KeyPath<InventoryItemSummary, String>,
        in items: [InventoryItemSummary]
    ) -> [String] {
        Array(Set(items.map { $0[keyPath: keyPath] }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func matchesSearch(_ item: InventoryItemSummary, searchText: String) -> Bool {
        let needle = normalized(searchText)
        return needle.isEmpty || normalized(item.searchableText).contains(needle)
    }

    private static func matchesExact(_ value: String, _ filter: String) -> Bool {
        filter.isEmpty || normalized(value) == normalized(filter)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

}
