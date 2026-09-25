import XCTest

/// Seed (P2-05 + P2-07): Milk 1 l in the Fridge (expires in 2 days, 459 HUF), Bread 1 pc in the Pantry
/// (expired yesterday), Apples 1.5 kg without a location (10 days), Eggs 10 pcs in the Fridge (20 days).
@MainActor
final class ProductsUITests: XCTestCase {
    private let nbsp = "\u{00A0}"

    private func openProducts() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed"])
        app.launch()
        app.openTab("Products")
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 10))
        return app
    }

    private func openDetail(_ name: String, in app: XCUIApplication) {
        let card = app.buttons["product.row.\(name)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    private func group(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["stock.group.\(name)"]
    }

    private func setAmount(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["amount.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The text is centred: tap the right end so the cursor lands after it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    func testCreateProduct() {
        let app = openProducts()
        app.buttons["addMenu"].firstMatch.tap()
        app.buttons["addMenu.product"].tap()
        let save = app.buttons["product.form.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let name = app.textFields["product.form.name"]
        name.tap()
        name.typeText("Paprika")
        let category = app.textFields["product.form.category"]
        category.tap()
        category.typeText("Spices")
        save.tap()
        XCTAssertTrue(app.buttons["product.row.Paprika"].waitForExistence(timeout: 5))
    }

    func testSearch() {
        let app = openProducts()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("egg")
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["product.row.Milk"].exists)
        search.typeText("zzz")
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForNonExistence(timeout: 3))
    }

    func testCategoryFilter() {
        let app = openProducts()
        app.buttons["products.filter"].tap()
        app.buttons["Dairy"].tap()
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["product.row.Milk"].exists)
        XCTAssertFalse(app.buttons["product.row.Bread"].exists)
    }

    func testCardsShowStockAndExpiry() {
        let app = openProducts()
        let milk = app.buttons["product.row.Milk"].label
        XCTAssertTrue(milk.contains("Mizo"), milk)
        XCTAssertTrue(milk.contains("1\(nbsp)l"), milk)
        XCTAssertTrue(milk.contains("2 days left"), milk)
        XCTAssertTrue(app.buttons["product.row.Bread"].label.contains("Expired yesterday"))
    }

    func testDetailSplitsInLandscape() {
        let app = openProducts()
        openDetail("Milk", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["product.detail.stack"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.descendants(matching: .any)["product.detail.split"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mizo"].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.descendants(matching: .any)["product.detail.stack"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Milk"].exists)
    }

    func testEditFromDetailKeepsDraftAcrossRotation() {
        let app = openProducts()
        openDetail("Milk", in: app)
        app.buttons["product.detail.edit"].tap()
        let name = app.textFields["product.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" 2")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertEqual(app.textFields["product.form.name"].value as? String, "Milk 2")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.navigationBars["Milk 2"].waitForExistence(timeout: 5))
    }

    func testProductLinkIsEditableAndOpensFromTheDetail() {
        let app = openProducts()
        openDetail("Milk", in: app)
        XCTAssertFalse(app.links["product.detail.link"].exists)
        app.buttons["product.detail.edit"].tap()
        let url = app.textFields["product.form.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("not a link")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.staticTexts["Enter a web address, for example shop.hu/milk."].waitForExistence(timeout: 3))
        url.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "mizo.hu")
        app.buttons["product.form.save"].tap()
        let link = app.links["product.detail.link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("mizo.hu"), link.label)
    }

    func testNoEatableFlagAnywhere() {
        let app = openProducts()
        XCTAssertFalse(app.buttons["product.row.Milk"].label.contains("Eatable"))
        openDetail("Milk", in: app)
        XCTAssertFalse(app.staticTexts["Eatable product"].exists)
        app.buttons["product.detail.edit"].tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Eatable"].exists)
    }

    func testDeleteProductFromDetailAndUndo() {
        let app = openProducts()
        openDetail("Bread", in: app)
        app.buttons["product.detail.edit"].tap()
        let delete = app.buttons["product.form.delete"]
        for _ in 0..<4 where !delete.exists { app.swipeUp() }
        delete.tap()
        let bread = app.buttons["product.row.Bread"]
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 5))
        XCTAssertFalse(bread.exists)
        let undo = app.buttons["undoToast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(bread.waitForExistence(timeout: 3))
    }

    func testConsumeFromDetailWithUndo() {
        let app = openProducts()
        openDetail("Eggs", in: app)
        let fridge = group("Fridge", in: app)
        XCTAssertTrue(fridge.waitForExistence(timeout: 5))
        XCTAssertTrue(fridge.label.contains("10\(nbsp)pcs"), fridge.label)
        keepScreenshot("Eggs detail", app)
        openStockMenu(in: app)
        keepScreenshot("Stock menu", app)
        app.buttons["stock.consume"].tap()
        XCTAssertTrue(app.textFields["amount.field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["amount.field"].value as? String, "10")
        setAmount("11", in: app)
        XCTAssertFalse(app.buttons["amount.confirm"].isEnabled)
        setAmount("4", in: app)
        app.buttons["amount.confirm"].tap()
        XCTAssertTrue(fridge.label.contains("6\(nbsp)pcs") || waitForLabel(fridge, containing: "6\(nbsp)pcs"))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(waitForLabel(fridge, containing: "10\(nbsp)pcs"))
    }

    func testPartialMoveSplitsTheItem() {
        let app = openProducts()
        openDetail("Eggs", in: app)
        openStockMenu(in: app)
        app.buttons["stock.move"].tap()
        setAmount("4", in: app)
        XCTAssertFalse(app.buttons["amount.confirm"].isEnabled)
        app.buttons["move.target.Pantry"].tap()
        XCTAssertTrue(app.buttons["amount.confirm"].isEnabled)
        app.buttons["amount.confirm"].tap()
        let pantry = group("Pantry", in: app)
        XCTAssertTrue(pantry.waitForExistence(timeout: 5))
        XCTAssertTrue(pantry.label.contains("4\(nbsp)pcs"), pantry.label)
        XCTAssertTrue(waitForLabel(group("Fridge", in: app), containing: "6\(nbsp)pcs"))
    }

    func testSwipeDeleteStockItemAndUndo() {
        let app = openProducts()
        openDetail("Apples", in: app)
        let loose = group("none", in: app)
        XCTAssertTrue(loose.waitForExistence(timeout: 5))
        app.buttons["stock.item"].firstMatch.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(loose.waitForNonExistence(timeout: 3))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(loose.waitForExistence(timeout: 3))
    }

    /// P4-05: the seeded milk was stocked for 459 HUF, so the price trend shows an average and a store line,
    /// and the store line opens the chart.
    func testPriceTrendShowsTheAverageAndOpensTheChart() {
        let app = openProducts()
        openDetail("Milk", in: app)
        let average = app.descendants(matching: .any)["price.average"]
        for _ in 0..<6 where !average.exists { app.swipeUp() }
        XCTAssertTrue(average.waitForExistence(timeout: 5))
        XCTAssertTrue(average.label.contains("459"), average.label)
        let store = app.buttons["price.store.none"]
        XCTAssertTrue(store.exists)
        keepScreenshot("product-price-trend", app)
        store.tap()
        XCTAssertTrue(app.descendants(matching: .any)["price.chart"].waitForExistence(timeout: 5))
        keepScreenshot("product-price-chart", app)
    }

    private func keepScreenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Stock item cards open their consume / move / delete menu on tap.
    private func openStockMenu(in app: XCUIApplication) {
        let item = app.buttons["stock.item"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons["stock.consume"].waitForExistence(timeout: 3))
    }

    func testStockMenuDeleteAndUndo() {
        let app = openProducts()
        openDetail("Milk", in: app)
        let fridge = group("Fridge", in: app)
        XCTAssertTrue(fridge.waitForExistence(timeout: 5))
        openStockMenu(in: app)
        app.buttons["stock.delete"].tap()
        XCTAssertTrue(fridge.waitForNonExistence(timeout: 3))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(fridge.waitForExistence(timeout: 3))
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
