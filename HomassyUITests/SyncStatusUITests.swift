import XCTest

/// P5-05, moved by P1-07a: the settings sheet's iCloud row, and a persistent problem shown the Apple-native way
/// (a red dot on the space menu and a callout at the top of the settings sheet, never over other screens).
final class SyncStatusUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLocalModeSaysSyncNeedsICloudAndShowsNoProblem() {
        let app = XCUIApplication.homassy()
        app.launch()
        XCTAssertEqual(app.buttons["spaceSwitcher"].firstMatch.label, "Personal")
        app.openSettings()

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
    func testAPersistentProblemMarksTheSpaceMenuAndShowsTheCallout() {
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSyncProblem"])
        app.launch()

        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        XCTAssertEqual(switcher.label, "Personal, sync problem")
        XCTAssertFalse(app.descendants(matching: .any)["sync.callout"].exists)   // not on Inventory
        let dot = XCTAttachment(screenshot: app.screenshot())
        dot.name = "space menu dot"
        dot.lifetime = .keepAlways
        add(dot)
        app.openSettings()

        let callout = app.descendants(matching: .any)["sync.callout"].firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 5))
        XCTAssertTrue(callout.label.contains("iCloud storage is full"), callout.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sync callout"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
