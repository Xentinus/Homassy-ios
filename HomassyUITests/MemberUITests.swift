import XCTest

/// P5-03 in local mode: first-visit member setup (name, colour), Later, and the Members section.
final class MemberUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Creates a household without the owner's name, so member setup is due for it.
    @MainActor
    private func createUnnamedHousehold(_ name: String, in app: XCUIApplication) {
        app.openTab("Household")
        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        app.buttons["New household"].firstMatch.tap()
        let field = app.textFields["household.new.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["household.new.create"].tap()
        let done = app.buttons["household.new.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    @MainActor
    func testFirstVisitAsksForNameAndColour() {
        let app = XCUIApplication.homassy()
        app.launch()
        createUnnamedHousehold("Second flat", in: app)

        let name = app.textFields["member.setup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8), "member setup was not offered")
        XCTAssertFalse(app.buttons["member.setup.save"].isEnabled)
        name.tap()
        name.typeText("Zoli")
        let mocha = app.buttons["member.color.mocha"]
        XCTAssertTrue(mocha.exists)
        mocha.tap()
        XCTAssertTrue(mocha.isSelected)
        attachScreenshot(app, "member setup")
        app.buttons["member.setup.save"].tap()

        let me = app.descendants(matching: .any)["member.row.me"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        XCTAssertTrue(me.label.contains("Zoli"), me.label)
        XCTAssertEqual(app.buttons["member.editSelf"].label, "Name, photo and colour")
        attachScreenshot(app, "members section")

        // Editing again shows the saved colour.
        app.buttons["member.editSelf"].tap()
        XCTAssertTrue(app.buttons["member.color.mocha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["member.color.mocha"].isSelected)
    }

    @MainActor
    func testLaterSkipsSetupAndLeavesASetYourNameRow() {
        let app = XCUIApplication.homassy()
        app.launch()
        createUnnamedHousehold("Third flat", in: app)

        let later = app.buttons["member.setup.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 8), "member setup was not offered")
        later.tap()

        let setName = app.buttons["member.editSelf"]
        XCTAssertTrue(setName.waitForExistence(timeout: 5))
        XCTAssertEqual(setName.label, "Set your name")
        XCTAssertFalse(app.textFields["member.setup.name"].exists)
    }

    @MainActor
    func testANamedOwnerIsNotAskedAgain() {
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")
        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        app.buttons["New household"].firstMatch.tap()
        let field = app.textFields["household.new.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Named flat")
        let owner = app.textFields["household.new.ownerName"]
        owner.tap()
        owner.typeText("Anna")
        app.buttons["household.new.create"].tap()
        app.buttons["household.new.done"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["member.row.me"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["member.setup.name"].waitForExistence(timeout: 2))
    }
}
