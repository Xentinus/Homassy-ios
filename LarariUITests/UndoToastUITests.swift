import XCTest

final class UndoToastUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication.larari(extraArguments: ["-uiTestUndoDemo"])
        app.launch()
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func delete(_ name: String, in app: XCUIApplication) {
        app.staticTexts[name].tap()  // opens the detail; delete lives only there (README "Card layout")
        app.buttons["Delete"].firstMatch.tap()
    }

    @MainActor
    func testDeleteShowsToastAndUndoRestoresTheRow() throws {
        let app = launchDemo()
        delete("Milk", in: app)

        XCTAssertTrue(app.staticTexts["Milk removed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Milk"].exists)

        XCTAssertEqual(app.buttons["undoToast.undo"].label, "Undo")
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Milk removed"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testToastLeavesAfterTheWindowAndTheDeleteSticks() throws {
        let app = launchDemo()
        delete("Milk", in: app)

        let toast = app.staticTexts["Milk removed"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Milk"].exists)
    }

    @MainActor
    func testTwoDeletesCollapseIntoOneToast() throws {
        let app = launchDemo()
        delete("Milk", in: app)
        XCTAssertTrue(app.staticTexts["Milk removed"].waitForExistence(timeout: 3))
        delete("Bread", in: app)

        XCTAssertTrue(app.staticTexts["2 items removed"].waitForExistence(timeout: 3))
        app.buttons["undoToast.undo"].tap()
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Bread"].exists)
    }

    @MainActor
    func testToastSitsAboveTheTabBar() throws {
        let app = launchDemo()
        delete("Milk", in: app)
        let toast = app.otherElements["undoToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(toast.frame.maxY, tabBar.frame.minY)
    }
}
