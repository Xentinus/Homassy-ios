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
    func testCreateListAndAddItemShowsTheCardStraightAway() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        XCTAssertTrue(app.navigationBars["Shopping"].exists, "no list to open: the card is on the tab itself")
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].exists)
        XCTAssertFalse(app.buttons["shopping.filter.all"].exists, "one list: no filter strip")
        XCTAssertFalse(app.descendants(matching: .any)["shopping.section.list.Weekly"].exists, "one list: no section header")
    }

    @MainActor
    func testPurchaseWithoutInventoryOnlyRemovesTheItemAndUndoBringsItBack() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].tap()
        let inventory = app.switches["shopping.purchase.addToInventory"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 5))
        XCTAssertEqual(inventory.value as? String, "1", "adding to inventory is the default")
        XCTAssertTrue(app.buttons["store.menu"].firstMatch.exists)
        inventory.switches.firstMatch.tap()
        XCTAssertFalse(app.buttons["store.menu"].firstMatch.waitForExistence(timeout: 1), "no store without inventory")
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
        let quantity = app.textFields["lot.1.quantity"]
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
    func testPurchaseInTwoLotsWithARecentStore() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].tap()
        XCTAssertTrue(app.textFields["lot.1.quantity"].waitForExistence(timeout: 5))
        app.buttons["lot.1.location"].firstMatch.tap()
        app.buttons["Fridge"].firstMatch.tap()
        app.buttons["lot.add"].tap()
        XCTAssertTrue(app.buttons["lot.2.remove"].waitForExistence(timeout: 3))
        app.buttons["lot.2.location"].firstMatch.tap()
        app.buttons["Pantry"].firstMatch.tap()
        app.buttons["store.menu"].firstMatch.tap()
        let corner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Corner Shop")).firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 3))
        corner.tap()
        XCTAssertFalse(app.switches["shopping.purchase.keepRemainder"].exists, "2 of 1 bought: nothing remains")
        attachScreenshot(app, named: "shopping-purchase-two-lots")
        app.buttons["shopping.purchase.confirm"].tap()
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 2))

        app.openTab("Inventory")
        let cards = app.buttons.matching(identifier: "inventory.row.Napkins")
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: cards)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: 8), .completed, "one card in Fridge, one in Pantry")
    }

    @MainActor
    func testADeadlineWithinTwoWeeksIsShownOnTheCard() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")
        app.addShoppingItem("Candles")

        app.shoppingItemMenu("Napkins", action: "Edit")
        let deadline = app.switches["shopping.form.hasDeadline"]
        XCTAssertTrue(deadline.waitForExistence(timeout: 5))
        deadline.switches.firstMatch.tap()                    // defaults to tomorrow
        app.buttons["shopping.form.save"].tap()

        let card = app.buttons["shopping.item.Napkins"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Needed by"), card.label)
        attachScreenshot(app, named: "shopping-deadline-card")
    }

    @MainActor
    func testStepwiseAdd() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")

        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.shoppingItem"].firstMatch.tap()
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
        app.buttons["addMenu.shoppingList"].firstMatch.tap()
        XCTAssertTrue(app.textFields["shopping.listEditor.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["color.custom"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testMenuDeleteThenUndo() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.shoppingItemMenu("Napkins", action: "Delete")
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 1))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 3))
    }

    // Drag to reorder is not UI-tested: XCUITest drag and drop on the list is unreliable on the device
    // (2026-09-25). `ShoppingOverviewModelTests.listMoveOffsetsReorderWithinTheSection` covers the reordering, and the manual
    // checklist covers the gesture.

    @MainActor
    func testRotationKeepsTheFilterAndOneCentredColumn() {
        let app = XCUIApplication.launchedOnShoppingTab()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")
        app.addShoppingItem("Napkins", list: "Weekly")
        app.addShoppingItem("Candles", list: "Weekly")
        app.selectShoppingFilter("Weekly")

        XCUIDevice.shared.orientation = .landscapeLeft
        let napkins = app.buttons["shopping.item.Napkins"]
        let candles = app.buttons["shopping.item.Candles"]
        XCTAssertTrue(napkins.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["shopping.filter.Weekly"].isSelected)
        XCTAssertEqual(napkins.frame.minX, candles.frame.minX, accuracy: 1, "one column in landscape too")
        XCTAssertLessThanOrEqual(napkins.frame.width, 681, "the column stops at 680 pt")
        attachScreenshot(app, named: "shopping-cards-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(napkins.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSwipeLeftDeletesThenUndo() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")
        app.addShoppingItem("Candles")

        let napkins = app.buttons["shopping.item.Napkins"]
        napkins.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }   // a short swipe reveals it, a full swipe deletes
        XCTAssertTrue(napkins.waitForNonExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertTrue(napkins.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSwipeRightOpensTheEditSheet() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.addShoppingItem("Napkins")

        app.buttons["shopping.item.Napkins"].swipeRight()
        let edit = app.buttons["Edit"]
        if edit.waitForExistence(timeout: 2) { edit.tap() }
        XCTAssertTrue(app.switches["shopping.form.hasDeadline"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAllShowsEveryListAndAChipFilters() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")
        app.addShoppingItem("Napkins", list: "Weekly")
        app.addShoppingItem("Candles", list: "Party")

        XCTAssertTrue(app.buttons["shopping.filter.all"].isSelected)
        XCTAssertTrue(app.staticTexts["shopping.section.list.Weekly"].exists
                      || app.otherElements["shopping.section.list.Weekly"].exists)
        XCTAssertTrue(app.buttons["shopping.item.Napkins"].exists)
        XCTAssertTrue(app.buttons["shopping.item.Candles"].exists)
        XCTAssertEqual(app.buttons["shopping.filter.Party"].value as? String, "1 to buy")
        attachScreenshot(app, named: "shopping-home-all")

        app.selectShoppingFilter("Party")
        XCTAssertTrue(app.buttons["shopping.item.Candles"].exists)
        XCTAssertFalse(app.buttons["shopping.item.Napkins"].waitForExistence(timeout: 1))
        app.addShoppingItem("Balloons")                           // preset to the filtered list
        app.selectShoppingFilter(nil)
        XCTAssertEqual(app.buttons["shopping.filter.Party"].value as? String, "2 to buy")
        attachScreenshot(app, named: "shopping-cards-portrait")
    }

    @MainActor
    func testGroupingByStoreShowsStoreSectionsAndTheListOnTheCard() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")
        app.addShoppingItem("Napkins", list: "Weekly", store: "Corner Shop")
        app.addShoppingItem("Candles", list: "Party")

        app.chooseShoppingGrouping("By store")
        let store = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "shopping.section.store.Corner Shop")).firstMatch
        XCTAssertTrue(store.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["shopping.section.noStore"].exists)
        let napkins = app.buttons["shopping.item.Napkins"]
        XCTAssertTrue(napkins.label.contains("Weekly"), napkins.label)
        attachScreenshot(app, named: "shopping-home-by-store")

        app.chooseShoppingGrouping("By list")
        XCTAssertTrue(app.descendants(matching: .any)["shopping.section.list.Weekly"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testManageListsRenamesAndDeletes() {
        let app = XCUIApplication.launchedOnShoppingTab()
        app.createShoppingList(named: "Weekly")
        app.createShoppingList(named: "Party")

        app.buttons["shopping.more"].firstMatch.tap()
        app.buttons["Manage lists"].firstMatch.tap()
        let party = app.buttons["shopping.manage.row.Party"]
        XCTAssertTrue(party.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "shopping-manage-lists")
        party.tap()
        let field = app.textFields["shopping.listEditor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" 2")
        app.buttons["shopping.listEditor.save"].tap()
        XCTAssertTrue(app.buttons["shopping.manage.row.Party 2"].waitForExistence(timeout: 5))

        app.buttons["shopping.manage.done"].tap()
        XCTAssertTrue(app.buttons["shopping.filter.Party 2"].waitForExistence(timeout: 5))

        // Long press on a chip: Delete, confirmed. One list left, so the strip goes away.
        app.buttons["shopping.filter.Party 2"].press(forDuration: 1.0)
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons["Delete list"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["shopping.filter.all"].waitForNonExistence(timeout: 5))
    }
}
