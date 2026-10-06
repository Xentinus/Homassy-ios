import XCTest

extension XCUIApplication {
    /// Seeded store (P2-05's -uiTestSeed) through P1-05's `larari(...)` helper (fake account,
    /// English UI, tips hidden, introduction skipped), Shopping tab open.
    static func launchedOnShoppingTab(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.larari(extraArguments: ["-uiTestSeed"] + extraArguments)
        app.launch()
        app.openTab("Shopping")
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 15))
        return app
    }

    func createShoppingList(named name: String) {
        buttons["addMenu"].firstMatch.tap()
        buttons["addMenu.shoppingList"].firstMatch.tap()
        let field = textFields["shopping.listEditor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        buttons["shopping.listEditor.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    /// Taps a chip on the filter strip; `nil` is "All". The strip shows only with two or more lists.
    func selectShoppingFilter(_ name: String?) {
        let chip = buttons[name.map { "shopping.filter.\($0)" } ?? "shopping.filter.all"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(chip.isSelected)
    }

    /// Adds an item through the stepwise sheet: a custom name (not one of the seeded products), 1 piece. `list`
    /// picks the list on the first step (needs two or more lists); `store` taps a recent store on the last step
    /// (the seed has "Corner Shop"), otherwise no store.
    func addShoppingItem(_ name: String, list: String? = nil, store: String? = nil) {
        buttons["addMenu"].firstMatch.tap()
        buttons["addMenu.shoppingItem"].firstMatch.tap()
        let query = textFields["shopping.add.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        if let list {
            buttons["shopping.add.list"].firstMatch.tap()
            let option = buttons[list].firstMatch             // menu items: by label, not identifier
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()
        }
        query.tap()
        query.typeText(name)
        buttons["shopping.add.next"].tap()
        XCTAssertTrue(textFields["shopping.add.quantity"].waitForExistence(timeout: 5))
        buttons["shopping.add.next"].tap()
        let confirm = buttons["shopping.add.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        if let store {
            let row = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", store)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3))
            row.tap()
        }
        confirm.tap()
        XCTAssertTrue(buttons["shopping.item.\(name)"].waitForExistence(timeout: 5))
    }

    /// "•••" → a grouping option, by its English label ("By list", "By store").
    func chooseShoppingGrouping(_ label: String) {
        buttons["shopping.more"].firstMatch.tap()
        let option = buttons[label].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    /// Long-press menu on an item card.
    func shoppingItemMenu(_ name: String, action: String) {
        buttons["shopping.item.\(name)"].press(forDuration: 1.0)
        let item = buttons[action].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
    }
}
