import XCTest

final class IntroductionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchShowsIntroductionOnceThenTheGate() throws {
        let app = XCUIApplication.homassy(accountState: "noAccount", skipIntroduction: false,
                                          extraArguments: ["-resetIntroduction"])
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip"].exists)
        XCTAssertFalse(app.staticTexts["iCloud is required"].exists)

        for title in ["Know what's at home", "Shopping made simple", "Personal and shared",
                      "Stay ahead of expiry dates"] {
            app.swipeLeft()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3), "Page \(title) not shown")
        }
        XCTAssertFalse(app.buttons["Skip"].exists)

        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["iCloud is required"].waitForExistence(timeout: 10))

        app.terminate()
        let relaunched = XCUIApplication.homassy(accountState: "noAccount", skipIntroduction: false)
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["iCloud is required"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.staticTexts["Welcome to Homassy"].exists)
    }

    @MainActor
    func testSkipGoesStraightToTheMainShell() throws {
        let app = XCUIApplication.homassy(accountState: "available", skipIntroduction: false,
                                          extraArguments: ["-resetIntroduction"])
        app.launch()

        let skip = app.buttons["introduction.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        XCTAssertEqual(skip.label, "Skip")
        skip.tap()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testNextButtonAdvances() throws {
        let app = XCUIApplication.homassy(accountState: "noAccount", skipIntroduction: false,
                                          extraArguments: ["-resetIntroduction"])
        app.launch()

        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Know what's at home"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLandscapeShowsTheSamePage() throws {
        let app = XCUIApplication.homassy(accountState: "noAccount", skipIntroduction: false,
                                          extraArguments: ["-resetIntroduction"])
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].isHittable)
    }
}
