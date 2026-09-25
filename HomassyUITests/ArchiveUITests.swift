import XCTest

final class ArchiveUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed"] + extra)
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testExportOpensTheSystemExporter() {
        let app = launch()
        app.openTab("Household")
        let export = app.buttons["archive.export"]
        var swipes = 0
        while !(export.exists && export.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(export.isHittable)
        export.tap()

        // The document picker in export mode offers "Move" (or "Save" on some iOS builds).
        let picker = app.buttons["Move"].waitForExistence(timeout: 10) || app.buttons["Save"].waitForExistence(timeout: 2)
        attachScreenshot(app, "exporter")
        XCTAssertTrue(picker, "the .fileExporter sheet did not appear")
    }

    @MainActor
    func testOpenedArchiveShowsPreviewCountsAndImports() {
        let app = launch(["-uiTestImportFixture"])

        let products = app.staticTexts["import.count.products"]
        XCTAssertTrue(products.waitForExistence(timeout: 15))
        attachScreenshot(app, "import preview")
        XCTAssertEqual(products.label, "2")
        XCTAssertEqual(app.staticTexts["import.count.members"].label, "2")
        XCTAssertEqual(app.staticTexts["import.count.storageLocations"].label, "1")

        let events = app.staticTexts["import.count.inventoryEvents"]
        if !events.exists { app.swipeUp() }
        XCTAssertEqual(events.label, "4")

        let name = app.textFields["import.newSpaceName"]
        var swipes = 0
        while !name.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertEqual(name.value as? String, "Otthon")

        app.buttons["import.confirm"].tap()
        XCTAssertTrue(app.staticTexts["import.done"].waitForExistence(timeout: 10))
        attachScreenshot(app, "import done")
        app.buttons["import.close"].tap()
        XCTAssertFalse(app.staticTexts["import.done"].exists)

        // The imported household is selected.
        let switcher = app.buttons["spaceSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertTrue(switcher.label.contains("Otthon"), "switcher shows \(switcher.label)")
    }
}
