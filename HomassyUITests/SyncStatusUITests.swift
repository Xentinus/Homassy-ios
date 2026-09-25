import XCTest

/// P5-05: the Household tab's iCloud row, and a persistent problem shown the Apple-native way
/// (a badge on the Household tab and a callout at the top of it, never over other screens).
final class SyncStatusUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLocalModeSaysSyncNeedsICloudAndShowsNoProblem() {
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")

        let row = app.descendants(matching: .any)["sync.status"].firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Sync needs iCloud"), row.label)
        XCTAssertFalse(app.descendants(matching: .any)["sync.callout"].exists)
    }

    @MainActor
    func testAPersistentProblemBadgesTheHouseholdTabAndShowsTheCallout() {
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSyncProblem"])
        app.launch()

        let tab = app.tabBars.buttons["Household"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["sync.callout"].exists)   // not on Inventory
        tab.tap()

        let callout = app.descendants(matching: .any)["sync.callout"].firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 5))
        XCTAssertTrue(callout.label.contains("iCloud storage is full"), callout.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sync callout"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
