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
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["shopping.list.Weekly"].label.contains("1 to buy"))
    }

    @MainActor
    func testPurchaseWithoutInventoryOnlyRemovesTheItemAndUndoBringsItBack() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].tap()
        let inventory = app.switches["shopping.purchase.addToInventory"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 5))
        XCTAssertEqual(inventory.value as? String, "1", "adding to inventory is the default")
        XCTAssertTrue(app.buttons["store.suggestion"].exists)
        inventory.switches.firstMatch.tap()
        XCTAssertFalse(app.buttons["store.suggestion"].waitForExistence(timeout: 1), "no store without inventory")
        app.buttons["shopping.purchase.confirm"].tap()
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

        // Make it two first: long press → Edit.
        app.shoppingItemMenu("Napkins", action: "Edit")
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
        XCTAssertTrue(app.buttons["liter"].exists || app.staticTexts["liter"].exists,
                      "the unit picker shows the unit name without an amount")
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
    func testCustomListColourIsOffered() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.shoppingItem"].firstMatch.tap()
        XCTAssertTrue(app.textFields["shopping.listEditor.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["color.custom"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testMenuDeleteThenUndo() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.openShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.shoppingItemMenu("Napkins", action: "Delete")
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 1))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 3))
    }

    // Drag to reorder is not UI-tested: XCUITest drag and drop on the card grid is unreliable on the device
    // (2026-09-25). `ShoppingListModelTests.dragOntoAnotherCardMovesIt` covers the reordering, and the manual
    // checklist covers the gesture.

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
