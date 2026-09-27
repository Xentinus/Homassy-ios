import XCTest

/// Seed: Bread 1 pc in the Pantry (expired yesterday), Milk 1 l in the Fridge (2 days), Apples 1.5 kg without a
/// location (10 days), Eggs 10 pcs in the Fridge (20 days). So "Expiring soon" holds Bread, Milk and Apples,
/// and the Fridge section holds Eggs.
@MainActor
final class InventoryUITests: XCTestCase {
    private let nbsp = "\u{00A0}"

    private func openInventory(seeded: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: seeded ? ["-uiTestSeed"] : [])
        app.launch()
        app.openTab("Inventory")
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Opens the add-stock sheet from `+` and waits for the product list.
    private func openPicker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.stock"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        return search
    }

    func testSectionsExpiringFirstThenLocations() {
        let app = openInventory()
        let expiring = element("inventory.section.expiring", in: app)
        let fridge = element("inventory.section.Fridge", in: app)
        XCTAssertTrue(expiring.waitForExistence(timeout: 10))
        XCTAssertTrue(fridge.exists)
        XCTAssertFalse(element("inventory.section.Pantry", in: app).exists)
        XCTAssertLessThan(expiring.frame.minY, fridge.frame.minY)

        let bread = app.buttons["inventory.row.Bread"]
        let milk = app.buttons["inventory.row.Milk"]
        let eggs = app.buttons["inventory.row.Eggs"]
        XCTAssertTrue(bread.exists && milk.exists && app.buttons["inventory.row.Apples"].exists)
        XCTAssertLessThan(bread.frame.minY, fridge.frame.minY)
        XCTAssertGreaterThan(eggs.frame.minY, fridge.frame.minY)
        XCTAssertTrue(bread.label.contains("Expired yesterday"), bread.label)
        XCTAssertTrue(milk.label.contains("1\(nbsp)l"), milk.label)
        XCTAssertTrue(eggs.label.contains("10\(nbsp)pcs"), eggs.label)
    }

    func testLandscapeKeepsTheSections() {
        let app = openInventory()
        XCTAssertTrue(element("inventory.section.expiring", in: app).waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["inventory.row.Milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("inventory.section.expiring", in: app).exists)
    }

    func testCardOpensTheProductDetail() {
        let app = openInventory()
        let eggs = app.buttons["inventory.row.Eggs"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 10))
        eggs.tap()
        XCTAssertTrue(app.navigationBars["Eggs"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("stock.group.Fridge", in: app).exists)
    }

    func testAddStockForAnExistingProduct() {
        let app = openInventory()
        XCTAssertTrue(app.buttons["inventory.row.Bread"].waitForExistence(timeout: 10))
        _ = openPicker(app)
        XCTAssertEqual(app.buttons.matching(identifier: "picker.row.Bread").count, 2,
                       "Bread is listed under Recent (seeded stock) and under B")
        app.buttons["picker.row.Bread"].firstMatch.tap()
        let save = app.buttons["stock.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        replaceText(of: app.textFields["lot.1.quantity"], with: "2")
        save.tap()
        XCTAssertTrue(waitForLabel(app.buttons["inventory.row.Bread"], containing: "3\(nbsp)pcs"))
    }

    func testAddStockInTwoLotsWithAStore() {
        let app = openInventory()
        XCTAssertTrue(app.buttons["inventory.row.Bread"].waitForExistence(timeout: 10))
        let search = openPicker(app)
        search.tap()
        search.typeText("bread")
        app.buttons["picker.row.Bread"].firstMatch.tap()
        XCTAssertTrue(app.buttons["stock.save"].waitForExistence(timeout: 5))

        // Lot 1: Fridge, no expiry. Lot 2 copies it; then Pantry.
        app.buttons["lot.1.location"].firstMatch.tap()
        let fridge = app.buttons["Fridge"].firstMatch
        XCTAssertTrue(fridge.waitForExistence(timeout: 3))
        fridge.tap()
        let expiryButton = app.buttons["lot.1.expiry"].firstMatch
        XCTAssertTrue(expiryButton.waitForExistence(timeout: 3))
        expiryButton.tap()
        let noExpiry = app.buttons["lot.noExpiry"]
        XCTAssertTrue(noExpiry.waitForExistence(timeout: 3))
        noExpiry.tap()
        app.buttons["lot.add"].tap()
        XCTAssertTrue(app.buttons["lot.2.remove"].waitForExistence(timeout: 3))
        app.buttons["lot.2.location"].firstMatch.tap()
        app.buttons["Pantry"].firstMatch.tap()
        XCTAssertEqual(app.buttons["lot.2.location"].firstMatch.label, "Storage location, Pantry",
                       "the title is read once")

        app.buttons["store.menu"].firstMatch.tap()
        let cornerRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fő utca 1.")).firstMatch
        XCTAssertTrue(cornerRow.waitForExistence(timeout: 3), "the menu row shows the store's address")

        // The full picker's recent row shows the same address (spec assertion).
        // Menu rows do not publish their accessibility identifiers, so the row is found by its title.
        let other = app.buttons["Other store…"]
        XCTAssertTrue(other.waitForExistence(timeout: 3))
        other.tap()
        let recentRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fő utca 1.")).firstMatch
        XCTAssertTrue(recentRow.waitForExistence(timeout: 5), "the store picker's recent row shows the address")
        app.buttons["Cancel"].firstMatch.tap()

        app.buttons["store.menu"].firstMatch.tap()
        XCTAssertTrue(cornerRow.waitForExistence(timeout: 3))
        cornerRow.tap()
        XCTAssertTrue(app.buttons["store.menu"].firstMatch.label.contains("Corner Shop · Budapest"))
        app.buttons["store.menu"].firstMatch.tap()
        XCTAssertTrue(cornerRow.waitForExistence(timeout: 3))
        XCTAssertTrue(cornerRow.isSelected, "VoiceOver reads the chosen store as selected")
        attachScreenshot(app, named: "stock-two-lots-store-menu")
        // A tap on the checked row keeps (and confirms) the choice.
        cornerRow.tap()
        XCTAssertTrue(cornerRow.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["store.menu"].firstMatch.label.contains("Corner Shop · Budapest"))
        app.buttons["store.menu"].firstMatch.tap()
        XCTAssertTrue(cornerRow.waitForExistence(timeout: 3))
        XCTAssertTrue(cornerRow.isSelected, "the checked row stays chosen after a second tap")
        XCTAssertFalse(app.buttons["No store"].firstMatch.isSelected)
        cornerRow.tap()
        XCTAssertTrue(cornerRow.waitForNonExistence(timeout: 3))
        attachScreenshot(app, named: "stock-two-lots")
        app.buttons["stock.save"].tap()

        // Expiring soon (the seeded, expired Bread), Fridge and Pantry each show a Bread card.
        let cards = app.buttons.matching(identifier: "inventory.row.Bread")
        let three = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: cards)
        XCTAssertEqual(XCTWaiter().wait(for: [three], timeout: 5), .completed)
        XCTAssertTrue(element("inventory.section.Pantry", in: app).exists)
        attachScreenshot(app, named: "stock-two-lots-inventory")
    }

    func testLotRowsStackAtAccessibilitySizes() {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: [
            "-uiTestSeed", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
        ])
        app.launch()
        app.openTab("Inventory")
        XCTAssertTrue(app.buttons["inventory.row.Bread"].waitForExistence(timeout: 10))
        _ = openPicker(app)
        let bread = app.buttons["picker.row.Bread"].firstMatch
        XCTAssertTrue(bread.waitForExistence(timeout: 5))
        bread.tap()
        let location = app.buttons["lot.1.location"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(location.label, "Storage location, Pantry")

        // Each control sits under its title, at the leading edge.
        let expiry = app.buttons["lot.1.expiry"].firstMatch
        for (title, control) in [("Storage location", location), ("Expires", expiry)] {
            let text = app.staticTexts[title].firstMatch
            XCTAssertLessThanOrEqual(text.frame.maxY, control.frame.minY, "\(title) stacks")
            XCTAssertEqual(text.frame.minX, control.frame.minX, accuracy: 1)
        }
        attachScreenshot(app, named: "stock-lot-accessibility-size")
        expiry.tap()
        XCTAssertTrue(app.buttons["lot.noExpiry"].waitForExistence(timeout: 3))
    }

    func testAddStockWithANewProduct() {
        let app = openInventory()
        XCTAssertTrue(app.buttons["inventory.row.Bread"].waitForExistence(timeout: 10))
        let search = openPicker(app)
        search.tap()
        search.typeText("Paprika")
        let create = app.buttons["picker.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let name = app.textFields["product.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Paprika")
        app.buttons["product.form.save"].tap()
        let save = app.buttons["stock.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["inventory.row.Paprika"].waitForExistence(timeout: 5))
    }

    func testEditStockItemFromTheDetail() {
        let app = openInventory()
        let eggs = app.buttons["inventory.row.Eggs"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 10))
        eggs.tap()
        let item = app.buttons["stock.item"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertFalse(app.buttons["stock.transfer"].exists, "no other household to move to")
        app.buttons["stock.edit"].tap()
        let quantity = app.textFields["lot.1.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lot.add"].exists, "editing has one lot")
        replaceText(of: quantity, with: "8")
        app.buttons["stock.save"].tap()
        XCTAssertTrue(waitForLabel(element("stock.group.Fridge", in: app), containing: "8\(nbsp)pcs"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(app.buttons["inventory.row.Eggs"], containing: "8\(nbsp)pcs"))
    }

    func testEmptyInventoryOffersAddingStock() {
        let app = openInventory(seeded: false)
        XCTAssertTrue(app.staticTexts["Nothing in stock yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add to inventory"].exists)
    }
}
