import XCTest

@MainActor
final class BarcodeUITests: XCTestCase {
    private func scan(_ code: String, fromTab tab: String = "Search", extra: [String] = [],
                      before: (XCUIApplication) -> Void = { _ in }) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed", "-uiTestScannedBarcode", code] + extra)
        app.launch()
        before(app)
        app.openTab(tab)
        let menu = app.navigationBars[tab].buttons["addMenu"]         // P1-07's shared "+" menu, scoped to the tab
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["addMenu.barcode"].tap()
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testKnownBarcodeShowsActions() {
        let app = scan("5991234567890")
        let add = app.buttons["barcode.addToInventory"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Milk"].exists)
        XCTAssertTrue(app.buttons["barcode.checkStock"].isEnabled)
        XCTAssertFalse(app.buttons["barcode.addToList"].isEnabled, "the seed has no shopping list")
        XCTAssertTrue(app.staticTexts["This household has no shopping list yet. You can create one on the Shopping tab."]
            .exists)
    }

    func testKnownBarcodeAddsToShoppingList() {
        // The store item seed puts Milk on both "Weekly" and "Party"; the add makes a third Milk item.
        var milkBefore = 0
        let app = scan("5991234567890", extra: ["-uiTestSeedStoreItems"]) { app in
            app.openTab("Shopping")
            let milk = app.descendants(matching: .any).matching(identifier: "shopping.item.Milk")
            XCTAssertTrue(milk.firstMatch.waitForExistence(timeout: 10))
            milkBefore = milk.count
        }
        let toList = app.buttons["barcode.addToList"]
        XCTAssertTrue(toList.waitForExistence(timeout: 5))
        XCTAssertTrue(toList.isEnabled)
        XCTAssertFalse(app.staticTexts["This household has no shopping list yet. You can create one on the Shopping tab."]
            .exists)
        toList.tap()
        XCTAssertTrue(app.textFields["shopping.add.quantity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Milk"].exists, "the scanned product is already chosen")
        XCTAssertTrue(app.buttons["Cancel"].exists, "started with a product, so the first page offers Cancel")
        attachScreenshot(app, named: "barcode-add-to-list")
        app.buttons["shopping.add.next"].tap()
        let confirm = app.buttons["shopping.add.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "the add closes the whole scan flow")
        app.openTab("Shopping")
        let milk = app.descendants(matching: .any).matching(identifier: "shopping.item.Milk")
        wait(for: [expectation(for: NSPredicate(format: "count > %d", milkBefore), evaluatedWith: milk)], timeout: 10)
    }

    func testKnownBarcodeAddsToInventory() {
        let app = scan("5991234567890")
        app.buttons["barcode.addToInventory"].tap()
        let save = app.buttons["stock.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)                                  // Milk is preselected
        save.tap()
        app.openTab("Inventory")
        // One card per product per section (P2-08): both Milk items expire within 14 days, so they share a card.
        let milk = app.buttons["inventory.row.Milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "2 × 1\u{00A0}l"), evaluatedWith: milk)], timeout: 5)
    }

    func testCheckStockFromInventory() {
        let app = scan("5991234567890", fromTab: "Inventory")
        app.buttons["barcode.checkStock"].tap()
        XCTAssertTrue(app.staticTexts["Mizo · Dairy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Milk"].waitForExistence(timeout: 5), "the detail is pushed onto the Inventory stack")
    }

    func testUnknownBarcodeOpensPrefilledForm() {
        let app = scan("4000000000009")
        let barcode = app.textFields["product.form.barcode"]
        XCTAssertTrue(barcode.waitForExistence(timeout: 5))
        XCTAssertEqual(barcode.value as? String, "4000000000009")
        let name = app.textFields["product.form.name"]
        name.tap()
        name.typeText("Test Bar")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.buttons["product.row.Test Bar"].waitForExistence(timeout: 5))
    }
}
