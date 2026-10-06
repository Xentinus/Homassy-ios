import XCTest

/// P4-06: the reminders run in the background and have no screen. The UI test only proves that a launch with the
/// Settings switch off (`-storeRemindersEnabled NO`, the UserDefaults argument domain) works; the logic is unit-tested.
final class StoreRemindersUITests: XCTestCase {
    @MainActor
    func testTheAppRunsWithTheSettingsSwitchOff() {
        continueAfterFailure = false
        let app = XCUIApplication.larari(extraArguments: ["-uiTestSeed", "-storeRemindersEnabled", "NO"])
        app.launch()
        app.openTab("Shopping")
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 10))
    }
}
