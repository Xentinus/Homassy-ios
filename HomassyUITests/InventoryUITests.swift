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
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.stock"].tap()
        let save = app.buttons["stock.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        element("stock.product", in: app).firstMatch.tap()
        app.buttons["Bread"].firstMatch.tap()
        XCTAssertTrue(save.isEnabled)
        replaceText(of: app.textFields["stock.quantity"], with: "2")
        save.tap()
        XCTAssertTrue(waitForLabel(app.buttons["inventory.row.Bread"], containing: "3\(nbsp)pcs"))
    }

    func testAddStockWithANewProduct() {
        let app = openInventory()
        XCTAssertTrue(app.buttons["inventory.row.Bread"].waitForExistence(timeout: 10))
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.stock"].tap()
        let newProduct = app.buttons["stock.newProduct"]
        XCTAssertTrue(newProduct.waitForExistence(timeout: 5))
        newProduct.tap()
        let name = app.textFields["product.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Paprika")
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
        let quantity = app.textFields["stock.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
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
