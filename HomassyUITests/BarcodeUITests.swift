import XCTest

@MainActor
final class BarcodeUITests: XCTestCase {
    private func scan(_ code: String, fromTab tab: String = "Search") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed", "-uiTestScannedBarcode", code])
        app.launch()
        app.openTab(tab)
        let menu = app.navigationBars[tab].buttons["addMenu"]         // P1-07's shared "+" menu, scoped to the tab
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["addMenu.barcode"].tap()
        return app
    }

    func testKnownBarcodeShowsActions() {
        let app = scan("5991234567890")
        let add = app.buttons["barcode.addToInventory"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Milk"].exists)
        XCTAssertTrue(app.buttons["barcode.checkStock"].isEnabled)
        XCTAssertFalse(app.buttons["barcode.addToList"].isEnabled)
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
        XCTAssertTrue(app.staticTexts["Mizo"].waitForExistence(timeout: 5))
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
