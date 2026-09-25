import XCTest

final class ShoppingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCreateListAndAddItem() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        XCTAssertTrue(app.navigationBars["Weekly"].exists)
        XCTAssertFalse(app.shoppingItemToggle("Napkins").isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["shopping.list.Weekly"].label.contains("1 to buy"))
    }

    @MainActor
    func testCheckboxPurchasesAndUndoRestores() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        let toggle = app.shoppingItemToggle("Napkins")
        toggle.tap()
        XCTAssertTrue(toggle.isSelected)
        XCTAssertTrue(app.buttons["shopping.detail.purchasedToggle"].exists)

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertFalse(toggle.isSelected)
        XCTAssertFalse(app.buttons["shopping.detail.purchasedToggle"].exists)
    }

    @MainActor
    func testSwipeDeleteThenUndo() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 1))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDragReorders() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        for name in ["Napkins", "Candles", "Foil"] { app.addShoppingItem(name) }

        let napkins = app.buttons["shopping.item.Napkins"]
        let foil = app.buttons["shopping.item.Foil"]
        XCTAssertLessThan(napkins.frame.minY, foil.frame.minY)
        app.navigationBars["Weekly"].staticTexts["Weekly"].firstMatch.tap()   // closes the keyboard
        foil.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.5, thenDragTo: napkins.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))

        XCTAssertLessThan(foil.frame.minY, napkins.frame.minY)
    }

    @MainActor
    func testCustomItemCardOpensTheForm() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].tap()
        let name = app.textFields["shopping.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Napkins")
        XCTAssertFalse(app.shoppingItemToggle("Napkins").isSelected, "opening the card does not tick it")
    }

    @MainActor
    func testSuggestionAddsTheProductAndTheCardOpensTheDetail() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")

        let field = app.textFields["shopping.addItem.field"]
        field.tap()
        field.typeText("Mil")
        let suggestion = app.buttons["shopping.suggestion.Milk"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        let milk = app.buttons["shopping.item.Milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        app.addShoppingItem("Napkins")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "shopping-list-detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        milk.tap()
        XCTAssertTrue(app.descendants(matching: .any)["product.detail.stack"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRotationKeepsTheOpenListAndShowsTheGrid() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Weekly"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let weekly = app.buttons["shopping.list.Weekly"]
        let party = app.buttons["shopping.list.Party"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 3))
        XCTAssertTrue(party.exists)
        XCTAssertEqual(weekly.frame.minY, party.frame.minY, accuracy: 2, "compact height shows two columns")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(weekly.waitForExistence(timeout: 3))
        XCTAssertLessThan(weekly.frame.minY, party.frame.minY)
    }
}
