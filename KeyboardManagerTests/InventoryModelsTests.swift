import XCTest
@testable import KeyboardManager

final class InventoryModelsTests: XCTestCase {
    func testLocalBoardJSONReadsOldMountAndEmitsOrderedPluralIDs() throws {
        let board = Board(id: "one", name: "One")
        let data = try JSONEncoder().encode(board)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "keycapSetIDs")
        let decoder = JSONDecoder()
        func decode() throws -> Board {
            try decoder.decode(Board.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try decode().keycapSetIDs, [])
        json["keycapSetID"] = "base"
        XCTAssertEqual(try decode().keycapSetIDs, ["base"])
        json["keycapSetIDs"] = ["accent", "base"]
        let current = try decode()
        XCTAssertEqual(current.keycapSetIDs, ["accent", "base"])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        XCTAssertNil(encoded["keycapSetID"])
        XCTAssertEqual(encoded["keycapSetIDs"] as? [String], ["accent", "base"])
    }

    func testCompletingOneSidedMountsPreservesOrderAndMakesAllSetsSearchable() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "b", name: "Board", keycapSetIDs: ["base"])]
        snapshot.keycapSets = [
            KeycapSet(id: "accent", name: "Blue accent", mountedBoardID: "b"),
            KeycapSet(id: "base", name: "Ivory base")
        ]
        snapshot.completeOneSidedKeycapMounts()
        XCTAssertEqual(snapshot.boards[0].keycapSetIDs, ["base", "accent"])
        XCTAssertEqual(snapshot.keycapSets.map(\.mountedBoardID), ["b", "b"])
        let first = snapshot
        snapshot.completeOneSidedKeycapMounts()
        XCTAssertEqual(snapshot, first)
        let results = InventoryQuery.results(
            in: snapshot, kind: .board, filters: InventoryFilters(searchText: "Blue accent"), sort: .name
        )
        XCTAssertEqual(results.map(\.keycapsSummary), ["Ivory base, Blue accent"])
    }

    func testStringCatalogProvidesGermanAndEnglishAtRuntime() {
        XCTAssertEqual(L10n.text("Übersicht", language: "de"), "Übersicht")
        XCTAssertEqual(L10n.text("Übersicht", language: "en"), "Overview")
        XCTAssertEqual(
            L10n.text("%lld Einträge", language: "en", arguments: 3),
            "3 entries"
        )
    }

    func testPrimaryNavigationUsesOverviewGalleryCaptureOrder() {
        XCTAssertEqual(AppRoute.primary, [.overview, .gallery, .capture])
    }

    func testOverviewSortsPhotoCountsNumericallyAndKeycapNamesNaturally() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [
            Board(id: "ten", name: "A", legacyKeycapsName: "Kit 10", photoIDs: (1...10).map { "photo-\($0)" }),
            Board(id: "two", name: "Z", legacyKeycapsName: "Kit 2", photoIDs: ["p1", "p2"]),
            Board(id: "empty", name: "M")
        ]
        for field in [InventorySort.Field.photoCount, .keycaps] {
            func ids(_ order: SortOrder) -> [String] {
                InventoryQuery.results(in: snapshot, kind: .board, filters: InventoryFilters(),
                                       sort: InventorySort(field, order: order)).map(\.id)
            }
            XCTAssertEqual(ids(.forward), ["empty", "two", "ten"])
            XCTAssertEqual(ids(.reverse), ["ten", "two", "empty"])
        }
    }

    func testSwitchSortsUseIndependentNumericTotals() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "one"), Board(id: "two")]
        snapshot.switchSets = [
            SwitchSet(id: "a", name: "A", quantity: 12),
            SwitchSet(id: "b", name: "B", quantity: 100),
            SwitchSet(id: "c", name: "C", quantity: 30)
        ]
        snapshot.switchInstallations = [
            SwitchInstallation(switchSetID: "a", boardID: "one", quantity: 2),
            SwitchInstallation(switchSetID: "b", boardID: "one", quantity: 70),
            SwitchInstallation(switchSetID: "b", boardID: "two", quantity: 29)
        ]
        let orders: [(InventorySort.Field, [String])] = [
            (.quantity, ["a", "c", "b"]), (.installedQuantity, ["c", "a", "b"]), (.availableQuantity, ["b", "a", "c"])
        ]
        for (field, ascending) in orders {
            for order in [SortOrder.forward, .reverse] {
                let result = InventoryQuery.results(in: snapshot, kind: .switchSet, filters: InventoryFilters(),
                                                    sort: InventorySort(field, order: order))
                XCTAssertEqual(result.map(\.id), order == .forward ? ascending : Array(ascending.reversed()))
            }
        }
    }

    func testQuickFiltersCombineLocalPhotoMountAndSearchCriteria() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "board", name: "Studio")]
        snapshot.keycapSets = [
            KeycapSet(id: "free", name: "Terra Base", coverURL: "https://example.com/cover.jpg"),
            KeycapSet(id: "mounted", name: "Terra Accent", mountedBoardID: "board"),
            KeycapSet(id: "withPhoto", name: "Terra Novelties", photoIDs: ["photo"]),
            KeycapSet(id: "other", name: "Solar Base")
        ]
        let filters = InventoryFilters(searchText: "terra", withoutPhoto: true, unmountedOnly: true)
        let results = InventoryQuery.results(in: snapshot, kind: .keycapSet, filters: filters, sort: .name)
        XCTAssertEqual(results.map(\.id), ["free"])
        XCTAssertFalse(InventoryFilters(unmountedOnly: true).isEmpty(for: .artisanSet))
        XCTAssertTrue(InventoryFilters(unmountedOnly: true).isEmpty(for: .switchSet))
    }

    func testPrimaryDetailSortUsesAConcreteLabelForEachInventoryKind() {
        XCTAssertEqual(InventorySort.Field.primaryDetail.title(for: .board), "Format")
        XCTAssertEqual(InventorySort.Field.primaryDetail.title(for: .keycapSet), "Profil")
        XCTAssertEqual(InventorySort.Field.primaryDetail.title(for: .artisanSet), "Profil")
        XCTAssertEqual(InventorySort.Field.primaryDetail.title(for: .switchSet), "Typ")
    }

    func testAllV1PinValuesHaveStableDisplayNames() {
        XCTAssertEqual(SwitchPins.three.rawValue, "3")
        XCTAssertEqual(SwitchPins.five.rawValue, "5")
        XCTAssertEqual(SwitchPins.hallEffect.rawValue, "HE")
        XCTAssertEqual(SwitchPins.three.displayName, "3 PIN")
        XCTAssertEqual(SwitchPins.five.displayName, "5 PIN")
        XCTAssertEqual(SwitchPins.hallEffect.displayName, "HE")
    }

    func testAvailableSwitchQuantityNeverBecomesNegative() {
        let switches = SwitchSet(id: "switches-a", name: "Test", quantity: 70)
        let installations = [
            SwitchInstallation(switchSetID: "switches-a", boardID: "board-a", quantity: 40),
            SwitchInstallation(switchSetID: "switches-a", boardID: "board-b", quantity: 45)
        ]

        XCTAssertEqual(switches.installedQuantity(in: installations), 85)
        XCTAssertEqual(switches.availableQuantity(in: installations), 0)
    }

    func testMainPhotoMustBelongToBoardPhotoIDs() {
        let valid = Board(id: "board-a", photoIDs: ["photo-a"], mainPhotoID: "photo-a")
        let invalid = Board(id: "board-b", photoIDs: [], mainPhotoID: "photo-a")

        XCTAssertTrue(valid.hasValidMainPhoto)
        XCTAssertFalse(invalid.hasValidMainPhoto)
    }

    func testLegacyImportedPhotoPrefixResolvesInsideManagedPhotosDirectory() {
        let legacy = PhotoRecord(
            id: "photo-a",
            owner: PhotoOwner(type: .board, id: "board-a"),
            originalName: "photo-a.jpg",
            mimeType: .jpeg,
            pixelWidth: 1,
            pixelHeight: 1,
            addedAt: .now,
            relativeFileName: "Photos/photo-a.jpg"
        )
        let unsafe = PhotoRecord(
            id: "photo-a",
            owner: PhotoOwner(type: .board, id: "board-a"),
            originalName: "photo-a.jpg",
            mimeType: .jpeg,
            pixelWidth: 1,
            pixelHeight: 1,
            addedAt: .now,
            relativeFileName: "Photos/../photo-a.jpg"
        )

        XCTAssertEqual(legacy.managedFileName, "photo-a.jpg")
        XCTAssertNil(unsafe.managedFileName)
    }

    func testSnapshotCountsAllInventoryKinds() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "board-a")]
        snapshot.keycapSets = [KeycapSet(id: "keycap-a")]
        snapshot.artisanSets = [ArtisanSet(id: "artisan-a")]
        snapshot.switchSets = [SwitchSet(id: "switch-a")]

        XCTAssertEqual(snapshot.counts.totalItems, 4)
        XCTAssertEqual(snapshot.counts.value(for: .switchSet), 1)
    }

    func testPresentationKeepsUniqueExternalImportImagesSeparateFromLocalPhotos() throws {
        var snapshot = InventorySnapshot.empty
        snapshot.keycapSets = [
            KeycapSet(
                id: "keycap-a",
                name: "Imported",
                photoIDs: ["local-photo"],
                coverURL: "https://example.com/cover.png",
                externalImageURLs: [
                    "https://example.com/cover.png",
                    "https://example.com/detail.png"
                ]
            )
        ]

        let item = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .keycapSet).first
        )

        XCTAssertEqual(item.photoCount, 1)
        XCTAssertEqual(item.externalImageCount, 2)
        XCTAssertEqual(
            item.externalImageURLs,
            [
                "https://example.com/cover.png",
                "https://example.com/detail.png"
            ]
        )
    }

    func testBoardSpotlightMetadataIncludesLinkedKeycapsAndSwitchQuantities() throws {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [Board(id: "board-a", name: "Board", keycapSetIDs: ["keycap-a"])]
        snapshot.keycapSets = [KeycapSet(id: "keycap-a", name: "Keycaps")]
        snapshot.switchSets = [SwitchSet(id: "switch-a", name: "Switches")]
        snapshot.switchInstallations = [
            SwitchInstallation(switchSetID: "switch-a", boardID: "board-a", quantity: 68)
        ]

        let item = try XCTUnwrap(InventoryQuery.items(in: snapshot, kind: .board).first)
        let metadata = Dictionary(uniqueKeysWithValues: item.metadata.map { ($0.label, $0.value) })

        XCTAssertEqual(metadata[L10n.text("Keycaps")], "Keycaps")
        XCTAssertEqual(metadata[L10n.text("Switches")], "Switches · 68 Stück")
    }

    func testOverviewPresentationRestoresV1RelationsStockAndListsForAllKinds() throws {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [
            Board(
                id: "board-a",
                name: "Board A",
                keycapSetIDs: ["keycap-a"],
                photoIDs: ["board-photo"],
                mainPhotoID: "board-photo"
            )
        ]
        snapshot.keycapSets = [
            KeycapSet(
                id: "keycap-a",
                name: "Keycaps A",
                kits: ["Base", "Numpad"],
                mountedBoardID: "board-a"
            )
        ]
        snapshot.artisanSets = [
            ArtisanSet(
                id: "artisan-a",
                name: "Artisan A",
                tags: ["Resin", "Blue"],
                mountedBoardID: "board-a"
            )
        ]
        snapshot.switchSets = [
            SwitchSet(
                id: "switch-a",
                name: "Switch A",
                switchType: "Linear",
                operatingForce: "55g",
                quantity: 105
            )
        ]
        snapshot.switchInstallations = [
            SwitchInstallation(
                switchSetID: "switch-a",
                boardID: "board-a",
                quantity: 87
            )
        ]

        let board = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .board).first
        )
        XCTAssertEqual(board.keycapsSummary, "Keycaps A")
        XCTAssertEqual(board.switchesSummary, "Switch A · 87 Stück")
        XCTAssertEqual(board.mainPhotoID, "board-photo")

        let keycaps = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .keycapSet).first
        )
        XCTAssertEqual(keycaps.contentsSummary, "Base, Numpad")
        XCTAssertEqual(keycaps.mountedBoardSummary, "Board A")

        let artisan = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .artisanSet).first
        )
        XCTAssertEqual(artisan.contentsSummary, "Resin, Blue")
        XCTAssertEqual(artisan.mountedBoardSummary, "Board A")

        let switches = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .switchSet).first
        )
        XCTAssertEqual(switches.stockSummary, "105 / 87 / 18")
        XCTAssertEqual(switches.mountedBoardSummary, "Board A (87)")
        XCTAssertEqual(switches.operatingForce, "55g")
    }

    func testOverviewBoardUsesLegacyNamesUntilRelationsCanBeResolved() throws {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = [
            Board(
                id: "board-a",
                name: "Board A",
                legacyKeycapsName: "Legacy Caps",
                legacySwitchesName: "Legacy Switches"
            )
        ]

        let board = try XCTUnwrap(
            InventoryQuery.items(in: snapshot, kind: .board).first
        )

        XCTAssertEqual(board.keycapsSummary, "Legacy Caps")
        XCTAssertEqual(board.switchesSummary, "Legacy Switches")
    }

    func testPerformanceFilteringAndSortingLargeBoardInventory() {
        var snapshot = InventorySnapshot.empty
        snapshot.boards = (0..<5_000).map { index in
            Board(
                id: "board-\(index)",
                name: index.isMultiple(of: 10) ? "Aurora \(index)" : "Board \(index)",
                manufacturer: index.isMultiple(of: 2) ? "Maker A" : "Maker B",
                format: index.isMultiple(of: 3) ? "65%" : "TKL",
                remark: "Performance fixture \(index)"
            )
        }
        let filters = InventoryFilters(searchText: "Aurora", manufacturer: "Maker A")

        measure {
            let results = InventoryQuery.results(
                in: snapshot,
                kind: .board,
                filters: filters,
                sort: .name
            )
            XCTAssertEqual(results.count, 500)
        }
    }
}
