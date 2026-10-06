import XCTest

final class AccountGateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNoAccountShowsGateWithSettingsButton() throws {
        let app = XCUIApplication.larari(accountState: "noAccount")
        app.launch()

        XCTAssertTrue(app.staticTexts["iCloud is required"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["accountGate"].exists)
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertFalse(app.buttons["Try again"].exists)
    }

    @MainActor
    func testRestrictedShowsGate() throws {
        let app = XCUIApplication.larari(accountState: "restricted")
        app.launch()

        XCTAssertTrue(app.staticTexts["iCloud is required"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Screen Time")).firstMatch.exists)
    }

    @MainActor
    func testTemporarilyUnavailableOffersRetry() throws {
        let app = XCUIApplication.larari(accountState: "temporarilyUnavailable")
        app.launch()

        XCTAssertTrue(app.staticTexts["iCloud is temporarily unavailable"].waitForExistence(timeout: 10))
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["iCloud is temporarily unavailable"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCouldNotDetermineOffersRetry() throws {
        let app = XCUIApplication.larari(accountState: "couldNotDetermine")
        app.launch()

        XCTAssertTrue(app.staticTexts["Couldn't check iCloud"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    @MainActor
    func testAvailableAccountPassesTheGate() throws {
        let app = XCUIApplication.larari(accountState: "available")
        app.launch()

        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["iCloud is required"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["accountGate"].exists)
    }
}
