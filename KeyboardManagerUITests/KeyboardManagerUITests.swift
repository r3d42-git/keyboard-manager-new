import SQLite3
import XCTest

@MainActor
final class KeyboardManagerUITests: XCTestCase {
    func testEnglishPreferenceLocalizesRunningInterface() {
        continueAfterFailure = false
        let app = launchIsolatedApp(language: "en")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gallery"].exists)
        XCTAssertTrue(app.staticTexts["Capture"].exists)
        let newItem = app.descendants(matching: .any).matching(identifier: "collection.new").firstMatch
        XCTAssertTrue(newItem.exists)
        XCTAssertTrue(app.buttons["New board"].exists || newItem.label == "New board")
    }

    func testPrimaryNavigationOrderAndDirtyWindowCloseProtection() {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let overview = app.descendants(matching: .any)["sidebar.overview"]
        let gallery = app.descendants(matching: .any)["sidebar.gallery"]
        let capture = app.descendants(matching: .any)["sidebar.capture"]

        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        XCTAssertTrue(gallery.exists)
        XCTAssertTrue(capture.exists)
        XCTAssertLessThan(overview.frame.minY, gallery.frame.minY)
        XCTAssertLessThan(gallery.frame.minY, capture.frame.minY)

        capture.click()

        let nameField = app.textFields["capture.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("Ungespeicherter UI-Test")

        let closeButton = app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()

        let closeDialog = app.sheets.firstMatch
        XCTAssertTrue(closeDialog.waitForExistence(timeout: 3))
        let keepEditingButton = closeDialog.buttons["Weiter bearbeiten"]
        XCTAssertTrue(keepEditingButton.waitForExistence(timeout: 3))
        XCTAssertTrue(closeDialog.buttons["Änderungen verwerfen und schließen"].exists)
        keepEditingButton.click()
        XCTAssertTrue(app.windows.firstMatch.exists)
        XCTAssertTrue((nameField.value as? String)?.contains("UI-Test") == true)

        closeButton.click()
        XCTAssertTrue(closeDialog.waitForExistence(timeout: 3))
        let discardButton = closeDialog.buttons["Änderungen verwerfen und schließen"]
        XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
        discardButton.click()
        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 2))
    }

    func testOverviewPassesCoreAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let zoom = app.sliders["gallery.zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(zoom.waitForNonExistence(timeout: 3))

        let windowFrame = app.windows.firstMatch.frame
        try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { issue in
            // Ignore only disabled framework-owned containers that users cannot
            // focus: SwiftUI hosting groups and macOS' legacy Touch Bar surface.
            if let element = issue.element, !element.isEnabled {
                if element.elementType == .group || element.elementType == .touchBar {
                    return true
                }
            }
            if let element = issue.element,
               element.elementType == .group,
               element.frame == windowFrame {
                return true
            }
            XCTFail(
                "\(issue.compactDescription): \(issue.detailedDescription) "
                + "Element: \(String(describing: issue.element))"
            )
            return true
        }
    }

    func testEditingAndBrowsingCollectionWithKeyboard() {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        app.typeKey("n", modifierFlags: .command)
        let name = app.textFields["capture.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        let title = "Studio 75 Aluminium mit einer besonders langen Sonderedition"
        name.click()
        name.typeText(title)
        app.typeKey("s", modifierFlags: .command)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.item.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["overview.table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].exists)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.click()
        let details = app.sheets.firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        XCTAssertTrue(details.staticTexts[title].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(details.waitForExistence(timeout: 1))

        // The same query must still be active after switching presentation.
        let search = app.toolbars.firstMatch.descendants(matching: .textField).firstMatch
        let searchField = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : search
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.click()
        searchField.typeText("No matching board")
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 3))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 3))
        app.buttons["Filter zurücksetzen"].firstMatch.click()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }

    func testOverviewSortsAscendingAndDescendingByManufacturerHeader() throws {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let boards = [
            (name: "Atlas 65", manufacturer: "Zephyr"),
            (name: "Boreal 75", manufacturer: "Acme"),
            (name: "Cedar 80", manufacturer: "Meridian")
        ]
        for board in boards {
            app.typeKey("n", modifierFlags: .command)
            let name = app.textFields["capture.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 3))
            name.click()
            name.typeText(board.name)

            let manufacturer = app.textFields["Hersteller"]
            XCTAssertTrue(manufacturer.waitForExistence(timeout: 3))
            manufacturer.click()
            manufacturer.typeText(board.manufacturer)

            app.buttons["capture.save"].click()
            XCTAssertTrue(app.sliders["gallery.zoom"].waitForExistence(timeout: 5))
        }

        app.typeKey("1", modifierFlags: .command)
        let table = app.descendants(matching: .any)["overview.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        let atlas = app.staticTexts["Atlas 65"]
        let boreal = app.staticTexts["Boreal 75"]
        let cedar = app.staticTexts["Cedar 80"]
        for name in [atlas, boreal, cedar] {
            XCTAssertTrue(name.waitForExistence(timeout: 3))
        }

        func assertRowOrder(
            _ first: XCUIElement, _ second: XCUIElement, _ third: XCUIElement,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            XCTAssertLessThan(first.frame.minY, second.frame.minY, file: file, line: line)
            XCTAssertLessThan(second.frame.minY, third.frame.minY, file: file, line: line)
        }

        assertRowOrder(atlas, boreal, cedar)
        let header = try XCTUnwrap(
            app.windows.firstMatch.descendants(matching: .any)
                .matching(identifier: "Hersteller").allElementsBoundByIndex.first { element in
                    let frame = element.frame
                    return !frame.isEmpty && frame.maxY <= atlas.frame.minY
                },
            "Der Hersteller-Spaltenkopf muss oberhalb der ersten Tabellenzeile liegen."
        )
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        assertRowOrder(boreal, cedar, atlas)

        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        assertRowOrder(atlas, cedar, boreal)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.sliders["gallery.zoom"].waitForExistence(timeout: 3))
        let sortMenu = app.descendants(matching: .any).matching(identifier: "collection.sort").firstMatch
        sortMenu.click()
        app.menuItems["Aufsteigend"].click()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(boreal.waitForExistence(timeout: 3))
        assertRowOrder(boreal, cedar, atlas)
    }

    func testCollectionSortPersistsByInventoryKindAfterRestart() {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let sortMenu = app.descendants(matching: .any).matching(identifier: "collection.sort").firstMatch
        let galleryZoom = app.sliders["gallery.zoom"]
        let keyboardSort = (field: "Hersteller", direction: "Absteigend")
        let otherSorts = [
            (kind: "Keycap-Sets", field: "Zuletzt geändert", direction: "Aufsteigend"),
            (kind: "Artisans", field: "Tags", direction: "Absteigend"),
            (kind: "Switches", field: "Gesamt", direction: "Aufsteigend")
        ]

        func setSort(_ field: String, _ direction: String) {
            for title in [field, direction] {
                XCTAssertTrue(sortMenu.waitForExistence(timeout: 3))
                sortMenu.click()
                let item = app.menuItems[title]
                XCTAssertTrue(item.waitForExistence(timeout: 3), title)
                item.click()
            }
        }

        func assertSort(
            _ field: String, _ direction: String,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            XCTAssertTrue(sortMenu.waitForExistence(timeout: 3), file: file, line: line)
            XCTAssertEqual(sortMenu.value as? String, "\(field) · \(direction)", file: file, line: line)
        }

        XCTAssertTrue(galleryZoom.waitForExistence(timeout: 3))
        setSort(keyboardSort.field, keyboardSort.direction)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(galleryZoom.waitForNonExistence(timeout: 3))
        for sort in otherSorts {
            selectCollectionKind(sort.kind, in: app)
            setSort(sort.field, sort.direction)
        }

        app.terminate()
        app.launch()

        XCTAssertTrue(galleryZoom.waitForExistence(timeout: 5))
        assertSort(keyboardSort.field, keyboardSort.direction)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(galleryZoom.waitForNonExistence(timeout: 3))
        for sort in otherSorts {
            selectCollectionKind(sort.kind, in: app)
            assertSort(sort.field, sort.direction)
        }
    }

    func testDataToolsOpenReportFromEmptyCollection() {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }
        let report = app.buttons["sidebar.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["sidebar.backup"].exists)
        report.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertTrue(sheet.buttons["Weiter …"].exists)
        sheet.buttons["Abbrechen"].click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 1))
    }

    func testOwnBackupRestoresSavedCollectionThroughFilePanels() throws {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("Collection.zip")

        func addBoard(_ title: String) {
            app.typeKey("n", modifierFlags: .command)
            let field = app.textFields["capture.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.click()
            field.typeText(title)
            app.typeKey("s", modifierFlags: .command)
            XCTAssertTrue(app.sliders["gallery.zoom"].waitForExistence(timeout: 5))
            app.typeKey("1", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }

        addBoard("Saved Board")
        app.buttons["sidebar.backup"].click()
        // Native panels accept an absolute path in the Go to Folder sheet.
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path)
        app.typeKey(.return, modifierFlags: [])
        let fileName = app.textFields["saveAsNameTextField"]
        XCTAssertTrue(fileName.waitForExistence(timeout: 3))
        fileName.click()
        app.typeKey("a", modifierFlags: .command)
        fileName.typeText("Collection")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Im Finder zeigen"].waitForExistence(timeout: 8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        addBoard("After Backup")
        app.buttons["sidebar.restore"].click()
        let select = app.buttons["Sicherung auswählen …"]
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(destination.path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let restore = app.buttons["Wiederherstellen …"]
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        restore.click()
        app.buttons["Sammlung wiederherstellen"].click()
        XCTAssertTrue(app.staticTexts["Sammlung wiederhergestellt"].waitForExistence(timeout: 8))
        app.buttons["Fertig"].click()
        XCTAssertTrue(app.staticTexts["Saved Board"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["After Backup"].exists)
    }

    func testRestoreCanBeCancelledBeforeChoosingABackup() {
        let app = launchIsolatedApp()
        defer { app.terminate() }

        app.buttons["sidebar.restore"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.buttons["Sicherung auswählen …"].waitForExistence(timeout: 3))
        sheet.buttons["Abbrechen"].click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["sidebar.restore"].isEnabled)
    }

    func testMultipleKeycapsTypedSwitchCountAndGalleryZoom() throws {
        continueAfterFailure = false
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let zoom = app.sliders["gallery.zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        XCTAssertFalse(zoom.isEnabled)

        let name = app.textFields["capture.name"]
        let save = app.buttons["capture.save"]
        func addComponent(_ kind: String, _ title: String, stock: String? = nil) {
            app.typeKey("n", modifierFlags: .command)
            let picker = app.popUpButtons["capture.kind"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.click()
            app.menuItems[kind].click()
            name.click()
            name.typeText(title)
            if let stock {
                let field = app.textFields["capture.stock"]
                field.click()
                app.typeKey("a", modifierFlags: .command)
                field.typeText(stock)
            }
            save.click()
            XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        }
        let base = "GMK Klassiker Base"
        let child = "GMK Klassiker Artisan-Child-Kit Sonderedition"
        let switches = "Silent Tactile"
        addComponent("Keycap-Set", base)
        addComponent("Keycap-Set", child)
        addComponent("Switch", switches, stock: "100")

        app.typeKey("n", modifierFlags: .command)
        name.click()
        name.typeText("Studio 75")
        let connections = app.radioButtons["Verknüpfungen"]
        connections.click()
        let addKeycap = app.descendants(matching: .any).matching(identifier: "capture.addKeycap").firstMatch
        for set in [base, child] {
            addKeycap.click()
            app.menuItems[set].click()
        }
        app.descendants(matching: .any).matching(identifier: "capture.addSwitch").firstMatch.click()
        app.menuItems[switches].click()

        let quantity = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "capture.quantity.")).firstMatch
        func enterQuantity(_ text: String) {
            quantity.click()
            app.typeKey("a", modifierFlags: .command)
            quantity.typeText(text)
        }
        enterQuantity("101")
        XCTAssertFalse(save.isEnabled)
        enterQuantity("x")
        XCTAssertFalse(save.isEnabled)
        enterQuantity("87")
        XCTAssertTrue(save.isEnabled)
        save.click()

        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.item.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        zoom.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).click()
        let smallWidth = card.frame.width
        zoom.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
        let largeWidth = card.frame.width
        XCTAssertGreaterThan(largeWidth, smallWidth + 50)
        card.rightClick()
        app.menuItems["Bearbeiten"].click()
        connections.click()
        XCTAssertTrue(app.staticTexts[base].exists)
        XCTAssertTrue(app.staticTexts[child].exists)
        XCTAssertEqual(quantity.value as? String, "87")
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Board mit Base-Kit, Child-Kit und Switch-Stückzahl"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["capture.discard"].click()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let savedZoom = try XCTUnwrap(zoom.value as? NSObject)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["overview.table"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(zoom.value as? NSObject, savedZoom)
        XCTAssertGreaterThan(card.frame.width, smallWidth + 50)
    }

    func testSpotlightReturnsFromLinkedSetsToSameFilteredBoardAndPhoto() throws {
        continueAfterFailure = false
        let root = isolatedStorageURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedCollection(at: root)
        let app = launchIsolatedApp(root: root)
        defer { app.terminate() }

        let board = SeedCollection.boards[0]
        let card = app.buttons["gallery.item.\(board.id)"]
        let otherCard = app.buttons["gallery.item.\(SeedCollection.boards[1].id)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(otherCard.exists)
        let toolbarText = app.toolbars.firstMatch.descendants(matching: .textField).firstMatch
        let search = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : toolbarText
        search.click()
        search.typeText(board.name)
        XCTAssertTrue(otherCard.waitForNonExistence(timeout: 3))
        card.click()

        let details = app.sheets.firstMatch
        func assertTitle(_ name: String) {
            XCTAssertTrue(details.staticTexts[name].firstMatch.waitForExistence(timeout: 3), name)
        }

        assertTitle(board.name)
        let secondPhoto = details.buttons["spotlight-photo-\(board.photoIDs[1])"]
        XCTAssertTrue(secondPhoto.waitForExistence(timeout: 3))
        secondPhoto.click()
        XCTAssertTrue(details.staticTexts["2 von 2"].waitForExistence(timeout: 3))
        XCTAssertTrue(secondPhoto.isSelected)

        let linkedItems = [
            (kind: "keycapSet", item: SeedCollection.keycaps[0]),
            (kind: "artisanSet", item: SeedCollection.artisans[0]),
            (kind: "switchSet", item: SeedCollection.switches[0].item)
        ]
        let back = details.buttons["spotlight-back-to-board"]
        for (kind, item) in linkedItems {
            let link = details.links["spotlight-related-\(kind)-\(item.id)"]
            XCTAssertTrue(link.waitForExistence(timeout: 3), item.name)
            link.click()
            assertTitle(item.name)
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            if kind == "switchSet" {
                attachScreenshot("Switch-Details aus der gefilterten Keyboard-Galerie", of: details)
            }
            back.click()
            assertTitle(board.name)
            XCTAssertTrue(details.staticTexts["2 von 2"].waitForExistence(timeout: 3))
            XCTAssertTrue(secondPhoto.isSelected)
        }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(details.waitForNonExistence(timeout: 3))
        XCTAssertTrue(card.exists)
        XCTAssertFalse(otherCard.exists)
    }

    func testSwitchOverviewShowsAndNumericallySortsAllThreeStockColumns() throws {
        continueAfterFailure = false
        let root = isolatedStorageURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedCollection(at: root)
        let app = launchIsolatedApp(root: root)
        defer { app.terminate() }

        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let resizeHandle = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -3, dy: -3))
        resizeHandle.click(forDuration: 0.3, thenDragTo: origin.withOffset(CGVector(dx: 897, dy: 647)))
        XCTAssertEqual(window.frame.width, 900, accuracy: 4)
        app.typeKey("1", modifierFlags: .command)
        selectCollectionKind("Keycap-Sets", in: app)
        for identifier in ["collection.quickFilter.noPhoto", "collection.quickFilter.unmounted"] {
            XCTAssertTrue(app.checkBoxes[identifier].isHittable)
        }
        selectCollectionKind("Switches", in: app)
        let rows = SeedCollection.switches.map { app.staticTexts[$0.item.name] }
        for row in rows {
            XCTAssertTrue(row.waitForExistence(timeout: 3))
        }

        let columns = [
            (title: "Gesamt", ascending: [1, 2, 0]),
            (title: "Verbaut", ascending: [2, 1, 0]),
            (title: "Verfügbar", ascending: [1, 0, 2])
        ]
        let headers = try columns.map { column in
            try XCTUnwrap(
                app.windows.firstMatch.descendants(matching: .any)
                    .matching(identifier: column.title).allElementsBoundByIndex.first { element in
                        let frame = element.frame
                        return !frame.isEmpty && frame.maxY <= rows[0].frame.minY
                    },
                "Spaltenkopf \(column.title)"
            )
        }
        XCTAssertLessThan(headers[0].frame.midX, headers[1].frame.midX)
        XCTAssertLessThan(headers[1].frame.midX, headers[2].frame.midX)
        for header in headers { XCTAssertTrue(window.frame.contains(header.frame), header.debugDescription) }

        let table = app.descendants(matching: .any)["overview.table"]
        let values = ["120", "115", "5"].map { table.staticTexts[$0] }
        for value in values {
            XCTAssertTrue(value.exists, value.debugDescription)
            XCTAssertEqual(value.frame.midY, values[0].frame.midY, accuracy: 3)
        }
        XCTAssertLessThan(values[0].frame.midX, values[1].frame.midX)
        XCTAssertLessThan(values[1].frame.midX, values[2].frame.midX)
        attachScreenshot("Switch-Übersicht mit drei Bestandsspalten", of: app.windows.firstMatch)

        func assertOrder(_ indices: [Int], column: String) {
            let positions = indices.map { rows[$0].frame.minY }
            XCTAssertLessThan(positions[0], positions[1], column)
            XCTAssertLessThan(positions[1], positions[2], column)
        }

        for (column, header) in zip(columns, headers) {
            let target = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            target.click()
            assertOrder(column.ascending, column: column.title)
            target.click()
            assertOrder(Array(column.ascending.reversed()), column: column.title)
        }
    }

    func testQuickFiltersApplyInOverviewAndGalleryForSupportedKinds() throws {
        continueAfterFailure = false
        let root = isolatedStorageURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedCollection(at: root)
        let app = launchIsolatedApp(root: root)
        defer { app.terminate() }

        let noPhoto = app.checkBoxes["collection.quickFilter.noPhoto"]
        let unmounted = app.checkBoxes["collection.quickFilter.unmounted"]
        let kinds = [
            (name: "Keyboards", items: SeedCollection.boards, gallery: true, hasMounts: false),
            (name: "Keycap-Sets", items: SeedCollection.keycaps, gallery: true, hasMounts: true),
            (name: "Artisans", items: SeedCollection.artisans, gallery: true, hasMounts: true),
            (name: "Switches", items: SeedCollection.switches.map { $0.item }, gallery: false, hasMounts: false)
        ]

        func assertResults(
            _ items: [SeedItem], inGallery: Bool, matching includes: (SeedItem) -> Bool
        ) {
            for item in items {
                let element = inGallery ? app.buttons["gallery.item.\(item.id)"] : app.staticTexts[item.name]
                if includes(item) {
                    XCTAssertTrue(element.waitForExistence(timeout: 3), item.name)
                } else {
                    XCTAssertTrue(element.waitForNonExistence(timeout: 3), item.name)
                }
            }
        }

        app.typeKey("1", modifierFlags: .command)
        for kind in kinds {
            selectCollectionKind(kind.name, in: app)
            assertResults(kind.items, inGallery: false) { _ in true }
            XCTAssertTrue(noPhoto.waitForExistence(timeout: 3))
            XCTAssertEqual(unmounted.exists, kind.hasMounts)
            noPhoto.click()
            assertResults(kind.items, inGallery: false) { $0.photoIDs.isEmpty }

            if kind.gallery {
                app.typeKey("2", modifierFlags: .command)
                XCTAssertTrue(app.sliders["gallery.zoom"].waitForExistence(timeout: 3))
                assertResults(kind.items, inGallery: true) { $0.photoIDs.isEmpty }
                noPhoto.click()
                assertResults(kind.items, inGallery: true) { _ in true }
                if kind.hasMounts {
                    unmounted.click()
                    assertResults(kind.items, inGallery: true) { $0.mountedBoardID == nil }
                }

                app.typeKey("1", modifierFlags: .command)
                XCTAssertTrue(app.descendants(matching: .any)["overview.table"].waitForExistence(timeout: 3))
                if kind.hasMounts {
                    assertResults(kind.items, inGallery: false) { $0.mountedBoardID == nil }
                    noPhoto.click()
                    assertResults(kind.items, inGallery: false) {
                        $0.mountedBoardID == nil && $0.photoIDs.isEmpty
                    }
                    app.typeKey("2", modifierFlags: .command)
                    assertResults(kind.items, inGallery: true) {
                        $0.mountedBoardID == nil && $0.photoIDs.isEmpty
                    }
                    app.typeKey("1", modifierFlags: .command)
                }
            }
        }
    }

    private func selectCollectionKind(_ name: String, in app: XCUIApplication) {
        let toolbar = app.toolbars.firstMatch
        let popUp = toolbar.popUpButtons["collection.kind"]
        if popUp.exists {
            popUp.click()
            let option = popUp.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "\(name) ")).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3), name)
            option.click()
        } else {
            let optionLabel = NSPredicate(format: "label BEGINSWITH %@", "\(name) ")
            let option = toolbar.descendants(matching: .any).matching(optionLabel).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3), name)
            option.click()
        }
    }

    private func attachScreenshot(_ name: String, of element: XCUIElement) {
        let screenshot = XCTAttachment(screenshot: element.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func isolatedStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardManagerUITests-\(UUID().uuidString)", isDirectory: true)
    }

    private func seedCollection(at root: URL) throws {
        let current = root.appendingPathComponent("Current", isDirectory: true)
        let photos = current.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let pixel = try XCTUnwrap(Data(
            base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        ))
        for photo in SeedCollection.photos {
            try pixel.write(to: photos.appendingPathComponent(photo.fileName))
        }

        // The isolated store reads the same SQLite snapshot format as a regular collection.
        let snapshot = try JSONSerialization.data(withJSONObject: SeedCollection.snapshot)
        let hex = snapshot.map { String(format: "%02x", $0) }.joined()
        let sql = """
            CREATE TABLE app_snapshot (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                schema_version INTEGER NOT NULL,
                snapshot_json BLOB NOT NULL,
                updated_at REAL NOT NULL
            );
            PRAGMA user_version = 1;
            INSERT INTO app_snapshot VALUES (1, 1, X'\(hex)', 0);
            """
        var connection: OpaquePointer?
        let opened = sqlite3_open(current.appendingPathComponent("inventory.sqlite").path, &connection)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(opened, SQLITE_OK, "SQLite-Testbestand konnte nicht geöffnet werden.")
        let database = try XCTUnwrap(connection)
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, String(cString: sqlite3_errmsg(database)))
    }

    private func launchIsolatedApp(language: String? = nil, root: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments += ["-preferredLanguage", language ?? "de"]
        app.launchEnvironment["KEYBOARD_MANAGER_UI_TEST_ROOT"] = (root ?? isolatedStorageURL()).path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        return app
    }
}

private struct SeedItem {
    let id: String
    let name: String
    let photoIDs: [String]
    let mountedBoardID: String?

    init(_ id: String, _ name: String, photos: Int = 0, mountedBoardID: String? = nil) {
        self.id = id
        self.name = name
        photoIDs = (0..<photos).map { "\(id)-photo-\($0 + 1)" }
        self.mountedBoardID = mountedBoardID
    }

    func encoded(with fields: [String: Any]) -> [String: Any] {
        var entry = fields
        entry["id"] = id
        entry["name"] = name
        entry["createdAt"] = 0
        entry["updatedAt"] = 0
        entry["photoIDs"] = photoIDs
        entry["mainPhotoID"] = photoIDs.first
        entry["mountedBoardID"] = mountedBoardID
        return entry
    }
}

private enum SeedCollection {
    static let boards = [
        SeedItem("board-pilot", "Pilot 75", photos: 2),
        SeedItem("board-workbench", "Werkbank 65")
    ]
    static let keycaps = [
        SeedItem("keycap-mounted", "Keycaps Nord", photos: 1, mountedBoardID: "board-pilot"),
        SeedItem("keycap-mounted-no-photo", "Keycaps Ost", mountedBoardID: "board-workbench"),
        SeedItem("keycap-external-image", "Keycaps Süd"),
        SeedItem("keycap-spare-with-photo", "Keycaps West", photos: 1)
    ]
    static let artisans = [
        SeedItem("artisan-mounted", "Artisan Birke", photos: 1, mountedBoardID: "board-pilot"),
        SeedItem("artisan-mounted-no-photo", "Artisan Buche", mountedBoardID: "board-workbench"),
        SeedItem("artisan-spare", "Artisan Eiche"),
        SeedItem("artisan-spare-with-photo", "Artisan Esche", photos: 1)
    ]
    static let switches = [
        (item: SeedItem("switch-alpha", "Alpha Linear", photos: 1), total: 120, installed: 115, board: "board-pilot"),
        (item: SeedItem("switch-bravo", "Bravo Tactile"), total: 12, installed: 10, board: "board-workbench"),
        (item: SeedItem("switch-charlie", "Charlie Clicky"), total: 25, installed: 2, board: "board-workbench")
    ]

    struct SeedPhoto {
        let id: String
        let ownerID: String
        let ownerType: String
        var fileName: String { "\(id).gif" }

        var encoded: [String: Any] {
            [
                "id": id, "owner": ["type": ownerType, "id": ownerID],
                "originalName": fileName, "mimeType": "image/gif",
                "pixelWidth": 1, "pixelHeight": 1, "addedAt": 0, "relativeFileName": fileName
            ]
        }
    }

    static var photos: [SeedPhoto] {
        let groups = [
            ("board", boards), ("keycapSet", keycaps), ("artisanSet", artisans),
            ("switchSet", switches.map { $0.item })
        ]
        return groups.flatMap { ownerType, items in
            items.flatMap { item in
                item.photoIDs.map { SeedPhoto(id: $0, ownerID: item.id, ownerType: ownerType) }
            }
        }
    }

    static var snapshot: [String: Any] {
        let componentFields: [String: Any] = [
            "manufacturer": "", "profile": "", "material": "", "status": "owned",
            "sourceURL": "", "sourceShop": "", "notes": "", "coverURL": "",
            "externalImageURLs": [String](), "trelloCardID": "", "trelloListName": ""
        ]
        return [
            "metadata": ["schemaVersion": 1, "createdAt": 0, "updatedAt": 0, "preferredLanguage": "de"],
            "libraryValues": ["valuesByKey": [String: [String]]()],
            "boards": boards.map { board in
                board.encoded(with: [
                    "manufacturer": "Testwerk", "format": "75 %", "plate": "", "pcb": "",
                    "stabilizers": "", "remark": "", "legacyKeycapsName": "", "legacySwitchesName": "",
                    "keycapSetIDs": keycaps.filter { $0.mountedBoardID == board.id }.map(\.id)
                ])
            },
            "keycapSets": keycaps.map { item in
                var fields = componentFields
                fields["kits"] = [String]()
                if item.id == "keycap-external-image" {
                    fields["coverURL"] = "https://example.invalid/synthetic-keycaps.gif"
                }
                return item.encoded(with: fields)
            },
            "artisanSets": artisans.map { item in
                var fields = componentFields
                fields["tags"] = [String]()
                return item.encoded(with: fields)
            },
            "switchSets": switches.map { entry in
                entry.item.encoded(with: [
                    "quantity": entry.total, "switchType": "", "topHousingMaterial": "",
                    "bottomHousingMaterial": "", "stemMaterial": "", "springLength": "",
                    "springType": "", "preTravel": "", "totalTravel": "", "operatingForce": "",
                    "bottomOutForce": "", "pins": "5", "hasLEDDiffuser": false, "isFactoryLubed": false,
                    "importedBoardText": "", "importedBoardAllocations": [String](), "importSource": "",
                    "importRow": 0, "importKey": "", "importWarnings": [String](), "notes": ""
                ])
            },
            "switchInstallations": switches.map { entry in
                ["switchSetID": entry.item.id, "boardID": entry.board, "quantity": entry.installed]
            },
            "photos": photos.map(\.encoded)
        ]
    }
}
