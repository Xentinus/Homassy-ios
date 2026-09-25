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
        XCTAssertTrue(textFields["shopping.addItem.field"].waitForExistence(timeout: 5))
    }

    /// Adds a custom item (a name that is not one of the seeded products) through the add bar.
    func addShoppingItem(_ name: String) {
        let field = textFields["shopping.addItem.field"]
        field.tap()
        field.typeText(name + "\n")
        XCTAssertTrue(buttons["shopping.item.\(name)"].waitForExistence(timeout: 5))
    }

    func shoppingItemToggle(_ name: String) -> XCUIElement { buttons["shopping.item.\(name).toggle"] }
}
