import XCTest

extension XCUIApplication {
    /// Seeded store (P2-05's -uiTestSeed) through P1-05's `homassy(...)` helper (fake account,
    /// English UI, tips hidden, introduction skipped), Shopping tab open.
    static func launchedOnShoppingTab(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed"] + extraArguments)
        app.launch()
        app.openTab("Shopping")
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 15))
        return app
    }

    func createShoppingList(named name: String) {
        buttons["addMenu"].firstMatch.tap()
        buttons["addMenu.shoppingItem"].firstMatch.tap()
        let field = textFields["shopping.listEditor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        buttons["shopping.listEditor.save"].tap()
        XCTAssertTrue(buttons["shopping.list.\(name)"].waitForExistence(timeout: 5))
    }

    func openShoppingList(named name: String) {
        buttons["shopping.list.\(name)"].tap()
        XCTAssertTrue(buttons["shopping.detail.add"].waitForExistence(timeout: 5))
    }

    /// Adds an item through the stepwise sheet: a custom name (not one of the seeded products), 1 piece, any store.
    func addShoppingItem(_ name: String) {
        buttons["shopping.detail.add"].tap()
        let query = textFields["shopping.add.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText(name)
        buttons["shopping.add.next"].tap()
        XCTAssertTrue(textFields["shopping.add.quantity"].waitForExistence(timeout: 5))
        buttons["shopping.add.next"].tap()
        let confirm = buttons["shopping.add.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(buttons["shopping.item.\(name)"].waitForExistence(timeout: 5))
    }

    /// Long-press menu on an item card.
    func shoppingItemMenu(_ name: String, action: String) {
        buttons["shopping.item.\(name)"].press(forDuration: 1.0)
        let item = buttons[action].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
    }


    func shoppingItemToggle(_ name: String) -> XCUIElement { buttons["shopping.item.\(name).toggle"] }
}
