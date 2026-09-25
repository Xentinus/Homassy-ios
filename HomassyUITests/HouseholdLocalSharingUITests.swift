import XCTest

/// P5-02 in local mode: the sharing entry explains that sharing needs iCloud instead of opening the system sheet.
final class HouseholdLocalSharingUITests: XCTestCase {
    @MainActor
    func testMembersAndSharingExplainsThatSharingNeedsICloud() throws {
        continueAfterFailure = false
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")

        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        app.buttons["New household"].firstMatch.tap()
        let name = app.textFields["household.new.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test flat")
        app.buttons["household.new.create"].tap()
        let done = app.buttons["household.new.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let manage = app.buttons["household.sharing.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertEqual(manage.label, "Members and sharing")
        manage.tap()

        let alert = app.alerts["iCloud needed"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Sharing needs iCloud — available in the released app."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "icloud needed"
        attachment.lifetime = .keepAlways
        add(attachment)
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.exists)
    }
}
