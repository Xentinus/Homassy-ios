import XCTest

/// The Search tab is the product catalogue (P1-07a, user decision 2026-09-26; search itself is a user request of
/// 2026-09-24). Seed: Milk (5991234567890), Bread, Eggs, Apples.
@MainActor
final class SearchUITests: XCTestCase {
    private func launch(scanning code: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        var arguments = ["-uiTestSeed"]
        if let code { arguments += ["-uiTestScannedBarcode", code] }
        let app = XCUIApplication.homassy(extraArguments: arguments)
        app.launch()
        app.openTab("Search")
        return app
    }

    func testAnEmptyFieldShowsTheWholeCatalogue() {
        let app = launch()
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["product.row.Eggs"].exists)
        XCTAssertTrue(app.buttons["product.row.Apples"].exists)
        XCTAssertTrue(app.navigationBars["Search"].buttons["spaceSwitcher"].exists, "the catalogue belongs to a space")
    }

    func testTypingFindsProducts() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("egg")
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForNonExistence(timeout: 5))
        app.buttons["product.row.Eggs"].tap()
        XCTAssertTrue(app.navigationBars["Eggs"].waitForExistence(timeout: 5))
    }

    func testScanningAKnownBarcodeShowsTheProduct() {
        let app = launch(scanning: "5991234567890")
        let scan = app.buttons["search.barcode"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForNonExistence(timeout: 5))
    }

    func testScanningAnUnknownBarcodeOffersANewProduct() {
        let app = launch(scanning: "4000000000009")
        app.buttons["search.barcode"].tap()
        let create = app.buttons["search.createProduct"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let barcode = app.textFields["product.form.barcode"]
        XCTAssertTrue(barcode.waitForExistence(timeout: 5))
        XCTAssertEqual(barcode.value as? String, "4000000000009")
        let name = app.textFields["product.form.name"]
        name.tap()
        name.typeText("Test Bar")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.buttons["product.row.Test Bar"].waitForExistence(timeout: 5))
    }

    func testSectionIndexJumpsToALetter() {
        let app = launch()
        let index = app.descendants(matching: .any)["products.index"]
        XCTAssertTrue(index.waitForExistence(timeout: 10))
        index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)).press(forDuration: 0.2)
        XCTAssertTrue(app.buttons["product.row.Milk"].isHittable)
    }

    /// Apple's pattern (user decision 2026-09-25): the detail has one Edit icon and no "More" menu;
    /// deleting the product sits at the bottom of the edit form.
    func testDetailHasOneEditIconAndDeleteIsInTheForm() {
        let app = launch()
        app.buttons["product.row.Milk"].tap()
        let edit = app.buttons["product.detail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Milk"].staticTexts["Edit"].exists, "the edit button is an icon")
        XCTAssertFalse(app.buttons["product.detail.menu"].exists, "no More menu")
        edit.tap()
        let delete = app.buttons["product.form.delete"]
        for _ in 0..<4 where !delete.exists { app.swipeUp() }
        XCTAssertTrue(delete.exists)
    }

    func testLongPressOnACatalogueCardTogglesTheFavorite() {
        let app = launch()
        let milk = app.buttons["product.row.Milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 10))
        milk.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Favorite"].waitForExistence(timeout: 3))
        app.buttons["Favorite"].tap()
        let predicate = NSPredicate(format: "label CONTAINS %@", "Favorite")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: milk)], timeout: 5),
                       .completed)
    }
}
