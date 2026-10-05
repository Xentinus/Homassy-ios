import XCTest

/// N-02: XCUITest cannot long-press the Home Screen icon reliably, so `-uiTestQuickAction <type>` routes as if that
/// quick action was chosen, with the menu `QuickActionPlanner` builds from the seeded store. The long press itself
/// is in the manual checklist.
@MainActor
final class QuickActionsUITests: XCTestCase {
    private func launch(_ type: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed", "-uiTestQuickAction", type] + extra)
        app.launch()
        return app
    }

    func testScanBarcodeOpensTheScanFlow() {
        let app = launch("com.homassy.app.quick.scan", extra: ["-uiTestScannedBarcode", "5991234567890"])
        XCTAssertTrue(app.buttons["barcode.addToInventory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Milk"].exists)
    }

    func testOpenLastListFiltersTheShoppingHome() {
        let app = launch("com.homassy.app.quick.openList", extra: ["-uiTestSeedShoppingList"])
        XCTAssertTrue(app.buttons["shopping.item.Soap"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Shopping"].exists)
        XCTAssertTrue(app.buttons["shopping.filter.Weekly"].isSelected)
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].exists, "the other list is filtered out")
    }

    func testAddToListOpensTheAddSheetOnTheList() {
        let app = launch("com.homassy.app.quick.addToList", extra: ["-uiTestSeedShoppingList"])
        let query = app.textFields["shopping.add.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        // The Lista row is preset to Weekly: an item added without touching it lands there.
        query.tap()
        query.typeText("Candles")
        app.buttons["shopping.add.next"].tap()
        XCTAssertTrue(app.textFields["shopping.add.quantity"].waitForExistence(timeout: 5))
        app.buttons["shopping.add.next"].tap()
        let confirm = app.buttons["shopping.add.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["shopping.item.Candles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["shopping.filter.Weekly"].value as? String, "2 to buy")
        XCTAssertEqual(app.buttons["shopping.filter.Party"].value as? String, "1 to buy")
    }

    func testListActionsAreMissingWithoutAList() {
        // Nothing was ever added to a list, so the menu has no "Add to List"; the hook finds no item and nothing opens.
        let app = launch("com.homassy.app.quick.addToList")
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["shopping.add.query"].waitForExistence(timeout: 2))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// P2-08e: the quick action shows what expires, so it switches Inventory to the expiry bands (the seed has Bread
    /// expired yesterday, Milk in 2 days and Apples in 10).
    func testExpiringSoonOpensInventoryByExpiry() {
        let app = launch("com.homassy.app.quick.expiring")
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("inventory.section.expiry.expired", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("inventory.section.expiry.soon", in: app).exists)
        XCTAssertFalse(element("inventory.section.expiring", in: app).exists, "not the location grouping")
    }

    /// The same from a remembered "By name": `-uiTestInventoryGrouping name` stands in for having picked it earlier,
    /// because the quick action fires at launch, before a test could use the menu.
    func testExpiringSoonLeavesNameGroupingForExpiry() {
        let app = launch("com.homassy.app.quick.expiring", extra: ["-uiTestInventoryGrouping", "name"])
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("inventory.section.expiry.expired", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("inventory.section.letter.B", in: app).exists, "the letter sections are gone")
        XCTAssertFalse(element("inventory.index", in: app).exists)
    }
}
