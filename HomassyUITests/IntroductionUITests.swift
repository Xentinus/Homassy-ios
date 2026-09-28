import XCTest

/// P1-10 introduction, animated in P1-10a (user pick 1I · 2C · 3B · 4B · 5C · 8H · 6C, 2026-09-26).
final class IntroductionUITests: XCTestCase {
    /// Titles after the welcome page, in order.
    private let laterTitles = ["Completely free", "Know what's at home", "Shopping made simple",
                               "Personal and shared", "Your data is yours", "Stay ahead of expiry dates"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(accountState: String = "noAccount") -> XCUIApplication {
        let app = XCUIApplication.homassy(accountState: accountState, skipIntroduction: false,
                                          extraArguments: ["-resetIntroduction"])
        app.launch()
        return app
    }

    @MainActor
    func testFreeIsTheSecondPage() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Completely free"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Every feature is for everyone, with no subscription, no ads and no premium tier."].exists)
    }

    @MainActor
    func testFirstLaunchShowsIntroductionOnceThenTheGate() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip"].exists)
        XCTAssertFalse(app.staticTexts["iCloud is required"].exists)

        for title in laterTitles {
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
        let app = launch(accountState: "available")
        let skip = app.buttons["introduction.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        XCTAssertEqual(skip.label, "Skip")
        skip.tap()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLandscapeShowsTheSamePage() throws {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Welcome to Homassy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Completely free"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Next"].isHittable)
    }
}
