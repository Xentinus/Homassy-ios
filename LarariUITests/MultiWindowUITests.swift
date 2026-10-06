import XCTest

/// N-03: "Open in New Window" exists only where the system has several windows. On the iPhone the long-press
/// menus are unchanged. Arranging, dragging and closing windows on iPad is checked by hand (the task's manual
/// checklist), because XCUITest cannot drag across windows.
@MainActor
final class MultiWindowUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Two lists, so the chip strip shows.
    private func launchWithLists() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")
        return app
    }

    private func pressChip(_ name: String, in app: XCUIApplication) {
        let chip = app.buttons["shopping.filter.\(name)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.press(forDuration: 1.0)
    }

    private func pressSearchCard(_ name: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.larari(extraArguments: ["-uiTestSeed"])
        app.launch()
        app.openTab("Search")
        let card = app.buttons["product.row.\(name)"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1.0)
        return app
    }

    func testIPhoneListChipMenuHasNoOpenInNewWindow() throws {
        try XCTSkipIf(isPad, "iPhone only")
        let app = launchWithLists()
        pressChip("Weekly", in: app)
        XCTAssertTrue(app.buttons["Edit"].firstMatch.waitForExistence(timeout: 3), "the list menu opens")
        XCTAssertTrue(app.buttons["Delete"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Open in New Window"].exists)
    }

    func testIPhoneProductCardMenuHasNoOpenInNewWindow() throws {
        try XCTSkipIf(isPad, "iPhone only")
        let app = pressSearchCard("Milk")
        XCTAssertTrue(app.buttons["Favorite"].waitForExistence(timeout: 3), "the card menu opens")
        XCTAssertFalse(app.buttons["Open in New Window"].exists)
    }

    /// iPad: the chip menu starts with the item, and it opens a window with just that list (no strip, its own add).
    func testIPadListChipOpensAListWindow() throws {
        try XCTSkipUnless(isPad, "iPad only")
        let app = launchWithLists()
        pressChip("Weekly", in: app)
        let open = app.buttons["Open in New Window"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Edit"].firstMatch.exists)
        open.tap()
        XCTAssertTrue(app.buttons["shopping.window.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Weekly"].waitForExistence(timeout: 5))
    }

    /// iPad: a product card's menu starts with the item, and it opens a window with just the product.
    func testIPadProductCardOpensAProductWindow() throws {
        try XCTSkipUnless(isPad, "iPad only")
        let app = pressSearchCard("Milk")
        let open = app.buttons["Open in New Window"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Favorite"].exists)
        open.tap()
        XCTAssertTrue(app.navigationBars["Milk"].waitForExistence(timeout: 10))
    }
}
