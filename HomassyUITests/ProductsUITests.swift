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
        app.openTab("Search")
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 10))
        return app
    }

    private func openDetail(_ name: String, in app: XCUIApplication) {
        let card = app.buttons["product.row.\(name)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    private func stockHeader(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["product.detail.stockHeader"]
    }

    /// A stock lot row whose label contains `text` (its quantity, storage or expiry).
    private func lot(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'stock.item' AND label CONTAINS %@", text)).firstMatch
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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "a new product opens on the name field")
        let name = app.textFields["product.form.name"]
        name.tap()
        name.typeText("Paprika")
        app.buttons["product.form.category"].tap()
        let search = app.navigationBars["Category"].searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Spices")
        app.buttons["category.create"].tap()
        let categoryRow = app.buttons["product.form.category"]
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(categoryRow.label.contains("Spices"), categoryRow.label)
        save.tap()
        XCTAssertTrue(app.buttons["product.row.Paprika"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["product.row.Paprika"].label.contains("Nothing in stock"),
                      app.buttons["product.row.Paprika"].label)
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
        XCTAssertTrue(app.staticTexts["Mizo · Dairy"].exists)
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
        XCTAssertFalse(app.buttons["product.detail.link"].exists)
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
        let link = app.buttons["product.detail.link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue((link.value as? String)?.contains("mizo.hu") == true, "\(String(describing: link.value))")
    }

    func testNoEatableFlagAnywhere() {
        let app = openProducts()
        XCTAssertFalse(app.buttons["product.row.Milk"].label.contains("Eatable"))
        openDetail("Milk", in: app)
        XCTAssertFalse(app.staticTexts["Eatable product"].exists)
        app.buttons["product.detail.edit"].tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Eatable"].exists)
        XCTAssertFalse(app.switches["Favorite"].exists, "Favourite lives on the detail, not in the form (4A)")
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
        let header = stockHeader(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.label.contains("10\(nbsp)pcs"), header.label)
        XCTAssertTrue(lot(containing: "Fridge", in: app).exists)
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
        XCTAssertTrue(header.label.contains("6\(nbsp)pcs") || waitForLabel(header, containing: "6\(nbsp)pcs"))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(waitForLabel(header, containing: "10\(nbsp)pcs"))
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
        let pantry = lot(containing: "Pantry", in: app)
        XCTAssertTrue(pantry.waitForExistence(timeout: 5))
        XCTAssertTrue(pantry.label.contains("4\(nbsp)pcs"), pantry.label)
        XCTAssertTrue(waitForLabel(lot(containing: "Fridge", in: app), containing: "6\(nbsp)pcs"))
        XCTAssertTrue(stockHeader(in: app).label.contains("10\(nbsp)pcs"))
    }

    func testSwipeDeleteStockItemAndUndo() {
        let app = openProducts()
        openDetail("Apples", in: app)
        let row = app.buttons["stock.item"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nothing in stock"].exists)
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.descendants(matching: .any)["price.trend.chart"].exists)
        // The summary and the chart now sit above the store rows, which can be below the fold.
        let store = app.buttons["price.store.none"]
        for _ in 0..<3 where !store.exists || !store.isHittable { app.swipeUp() }
        XCTAssertTrue(store.exists)
        keepScreenshot("product-price-trend", app)
        store.tap()
        XCTAssertTrue(app.descendants(matching: .any)["price.chart"].waitForExistence(timeout: 5))
        keepScreenshot("product-price-chart", app)
    }

    func testHistoryShowsTheLastThreeAndOpensTheFullPage() {
        let app = openProducts()
        openDetail("Eggs", in: app)
        let showAll = app.buttons["history.showAll"]
        XCTAssertFalse(showAll.exists, "one event so far")
        for _ in 0..<3 {
            openStockMenu(in: app)
            app.buttons["stock.consume"].tap()
            setAmount("1", in: app)
            app.buttons["amount.confirm"].tap()
            XCTAssertTrue(app.textFields["amount.field"].waitForNonExistence(timeout: 3))
        }
        for _ in 0..<6 where !showAll.exists { app.swipeUp() }
        XCTAssertTrue(showAll.waitForExistence(timeout: 5))
        XCTAssertTrue(showAll.label.contains("4"), showAll.label)
        keepScreenshot("product-history-section", app)
        showAll.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history.page"].exists)
        keepScreenshot("product-history-page", app)
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
        let row = app.buttons["stock.item"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        openStockMenu(in: app)
        app.buttons["stock.delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
    }

    func testHeaderShowsTheBarcodeAndTheActions() {
        let app = openProducts()
        openDetail("Milk", in: app)
        XCTAssertTrue(app.staticTexts["product.detail.name"].waitForExistence(timeout: 5))
        let barcode = app.descendants(matching: .any)["product.detail.barcode"]
        XCTAssertTrue(barcode.exists)
        XCTAssertEqual(barcode.value as? String, "5991234567890")
        barcode.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3))
        app.buttons["Copy"].tap()
        let favorite = app.buttons["product.detail.favorite"]
        XCTAssertEqual(favorite.value as? String, "No")
        favorite.tap()
        XCTAssertTrue(waitForValue(favorite, "Yes"))
        XCTAssertFalse(app.buttons["product.detail.link"].exists, "no link on the seeded milk")
        keepScreenshot("product-detail-header", app)
    }

    func testPlusAddsStockOfThisProduct() {
        let app = openProducts()
        openDetail("Eggs", in: app)
        app.buttons["product.detail.add"].tap()
        let quantity = app.textFields["lot.1.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = quantity.value as? String ?? ""
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "3")
        app.buttons["stock.save"].tap()
        XCTAssertTrue(waitForLabel(stockHeader(in: app), containing: "13\(nbsp)pcs"))
    }

    func testListaIsDisabledWithoutAShoppingList() {
        let app = openProducts()
        openDetail("Milk", in: app)
        let toList = app.buttons["product.detail.addToList"]
        XCTAssertTrue(toList.waitForExistence(timeout: 5))
        XCTAssertFalse(toList.isEnabled)
    }

    func testListaAddsTheProductToAShoppingList() {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed", "-uiTestSeedStoreItems"])
        app.launch()
        app.openTab("Search")
        openDetail("Eggs", in: app)
        let toList = app.buttons["product.detail.addToList"]
        XCTAssertTrue(toList.waitForExistence(timeout: 5))
        XCTAssertTrue(toList.isEnabled)
        toList.tap()
        XCTAssertTrue(app.textFields["shopping.add.quantity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["shopping.add.list"].exists, "two lists, so the list row shows")
        XCTAssertTrue(app.staticTexts["Eggs"].exists, "the chosen product is named on the amount page")
        XCTAssertTrue(app.buttons["Cancel"].exists, "started with a product, so the first page offers Cancel")
        XCTAssertFalse(app.buttons["shopping.add.back"].exists, "and no Back to a page that does not exist")
        keepScreenshot("product-add-to-list", app)
        app.buttons["shopping.add.next"].tap()
        let confirm = app.buttons["shopping.add.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.openTab("Shopping")
        XCTAssertTrue(app.descendants(matching: .any)["shopping.item.Eggs"].waitForExistence(timeout: 10))
    }

    func testCategoryPickerPicksAnExistingCategory() {
        let app = openProducts()
        openDetail("Milk", in: app)
        app.buttons["product.detail.edit"].tap()
        let row = app.buttons["product.form.category"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Dairy"), row.label)
        row.tap()
        XCTAssertTrue(app.buttons["category.row.Dairy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category.row.Dairy"].isSelected)
        keepScreenshot("category-picker", app)
        app.buttons["category.row.Bakery"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Bakery"), row.label)
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.staticTexts["Mizo · Bakery"].waitForExistence(timeout: 5))
    }

    func testCancelAsksBeforeDroppingChanges() {
        let app = openProducts()
        openDetail("Milk", in: app)
        let edit = app.buttons["product.detail.edit"]
        edit.tap()
        let cancel = app.buttons["product.form.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        keepScreenshot("product-form-edit", app)
        cancel.tap()                                                   // nothing changed: closes at once
        XCTAssertTrue(app.navigationBars["Milk"].waitForExistence(timeout: 5))

        edit.tap()
        let name = app.textFields["product.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" 2")
        cancel.tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        keepScreenshot("product-form-discard", app)
        // The chosen behaviour: iOS 26 shows the dialog as a popover at the ✕ with only "Discard Changes"; a tap
        // outside it keeps editing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3)).tap()   // right of the centred photo header: clear of the keyboard, the popover and any control
        XCTAssertTrue(discard.waitForNonExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "Milk 2")
        cancel.tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.navigationBars["Milk"].waitForExistence(timeout: 5))
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
