import XCTest

final class ShoppingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCreateListAndAddItem() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        XCTAssertTrue(app.navigationBars["Weekly"].exists)
        XCTAssertTrue(app.shoppingItemToggle("Napkins").exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["shopping.list.Weekly"].label.contains("1 to buy"))
    }

    @MainActor
    func testCheckboxBuysAndUndoBringsItBack() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.shoppingItemToggle("Napkins").tap()
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 1))

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCardOpensThePurchaseSheetAndKeepsTheRemainder() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        // Make it two packs first: swipe right edits.
        app.buttons["shopping.item.Napkins"].swipeRight()
        app.buttons["Edit"].tap()
        let formQuantity = app.textFields["shopping.form.quantity"]
        XCTAssertTrue(formQuantity.waitForExistence(timeout: 5))
        formQuantity.tap()
        formQuantity.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        app.buttons["shopping.form.save"].tap()
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 5))

        app.buttons["shopping.item.Napkins"].tap()
        let quantity = app.textFields["shopping.purchase.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.value as? String, "2")
        quantity.tap()
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "1")
        let keep = app.switches["shopping.purchase.keepRemainder"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3))
        XCTAssertEqual(keep.value as? String, "1")
        attachScreenshot(app, named: "shopping-purchase-sheet")
        app.buttons["shopping.purchase.confirm"].tap()

        let card = app.buttons["shopping.item.Napkins"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("1"), card.label)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testStepwiseAdd() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")

        app.buttons["shopping.detail.add"].tap()
        let query = app.textFields["shopping.add.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Mil")
        let milk = app.buttons["shopping.add.suggestion.Milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        milk.tap()

        let quantity = app.textFields["shopping.add.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        app.buttons["shopping.add.next"].tap()

        let anyStore = app.buttons["shopping.add.anyStore"]
        XCTAssertTrue(anyStore.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "shopping-add-store-step")
        anyStore.tap()
        app.buttons["shopping.add.confirm"].tap()

        let card = app.buttons["shopping.item.Milk"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("2"), card.label)
    }

    @MainActor
    func testStepwiseAddOfACustomItemFromTheQuickBar() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")

        let field = app.textFields["shopping.addItem.field"]
        field.tap()
        field.typeText("Candles")
        app.buttons["shopping.addItem.steps"].tap()
        let custom = app.buttons["shopping.add.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap()
        app.buttons["shopping.add.next"].tap()
        XCTAssertTrue(app.buttons["shopping.add.confirm"].waitForExistence(timeout: 5))
        app.buttons["shopping.add.confirm"].tap()
        XCTAssertTrue(app.buttons["shopping.item.Candles"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomListColourIsOffered() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.shoppingItem"].firstMatch.tap()
        XCTAssertTrue(app.textFields["shopping.listEditor.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["color.custom"].firstMatch.waitForExistence(timeout: 3))
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
    func testRotationKeepsTheOpenListAndShowsTheGrid() {
        let app = XCUIApplication.launchedOnShoppingTab()
        defer { XCUIDevice.shared.orientation = .portrait }
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
