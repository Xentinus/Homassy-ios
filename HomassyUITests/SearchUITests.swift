import XCTest

/// The Search tab and barcode search (user request, 2026-09-24). Seed: Milk (5991234567890), Bread, Eggs, Apples.
@MainActor
final class SearchUITests: XCTestCase {
    private func launch(scanning code: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        var arguments = ["-uiTestSeed"]
        if let code { arguments += ["-uiTestScannedBarcode", code] }
        let app = XCUIApplication.homassy(extraArguments: arguments)
        app.launch()
        return app
    }

    private func openSearchTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    func testTypingFindsProducts() {
        let app = launch()
        openSearchTab(app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("egg")
        XCTAssertTrue(app.buttons["search.row.Eggs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.row.Milk"].exists)
        app.buttons["search.row.Eggs"].tap()
        XCTAssertTrue(app.navigationBars["Eggs"].waitForExistence(timeout: 5))
    }

    func testScanningAKnownBarcodeShowsTheProduct() {
        let app = launch(scanning: "5991234567890")
        openSearchTab(app)
        let scan = app.buttons["search.barcode"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.buttons["search.row.Milk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.row.Eggs"].exists)
    }

    func testScanningAnUnknownBarcodeOffersANewProduct() {
        let app = launch(scanning: "4000000000009")
        openSearchTab(app)
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
        XCTAssertTrue(app.buttons["search.row.Test Bar"].waitForExistence(timeout: 5))
    }

    func testProductsTabBarcodeSearch() {
        let app = launch(scanning: "5991234567890")
        app.openTab("Products")
        let scan = app.navigationBars["Products"].buttons["products.barcodeSearch"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()
        XCTAssertTrue(app.buttons["product.row.Milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["product.row.Eggs"].waitForNonExistence(timeout: 5))
    }

    func testSectionIndexJumpsToALetter() {
        let app = launch()
        app.openTab("Products")
        let index = app.descendants(matching: .any)["products.index"]
        XCTAssertTrue(index.waitForExistence(timeout: 10))
        index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)).press(forDuration: 0.2)
        XCTAssertTrue(app.buttons["product.row.Milk"].isHittable)
    }

    func testDetailEditIsAnIcon() {
        let app = launch()
        app.openTab("Products")
        app.buttons["product.row.Milk"].tap()
        let edit = app.buttons["product.detail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Milk"].staticTexts["Edit"].exists, "no Edit text next to the menu")
    }
}
