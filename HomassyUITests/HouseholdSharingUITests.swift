import XCTest

/// P5-01 in local mode: create a household from the space switcher, see its role, delete it.
final class HouseholdSharingUITests: XCTestCase {
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

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) not reachable")
    }

    /// Opens the New household sheet from the switcher and creates "Test flat" owned by "Anna".
    @MainActor
    private func createHousehold(in app: XCUIApplication) {
        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        let newHousehold = app.buttons["New household"].firstMatch
        XCTAssertTrue(newHousehold.waitForExistence(timeout: 5))
        newHousehold.tap()

        let name = app.textFields["household.new.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let create = app.buttons["household.new.create"]
        XCTAssertFalse(create.isEnabled)
        name.tap()
        name.typeText("Test flat")
        let owner = app.textFields["household.new.ownerName"]
        owner.tap()
        owner.typeText("Anna")
        attachScreenshot(app, "new household form")
        XCTAssertTrue(create.isEnabled)
        create.tap()

        XCTAssertTrue(app.staticTexts["“Test flat” is ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["household.new.export"].exists)
        attachScreenshot(app, "new household created")
    }

    @MainActor
    func testCreatingAHouseholdSelectsItAndDeletingItReturnsToPersonal() {
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 10))
        // Personal has no Sharing section.
        XCTAssertFalse(app.staticTexts["household.sharing.role"].exists)

        createHousehold(in: app)
        app.buttons["household.new.done"].tap()

        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertEqual(switcher.label, "Test flat")
        let role = app.staticTexts["household.sharing.role"]
        XCTAssertTrue(role.waitForExistence(timeout: 5))
        XCTAssertEqual(role.label, "Your role, Owner")
        XCTAssertTrue(app.buttons["archive.export"].exists)
        attachScreenshot(app, "household tab owner")

        let delete = app.buttons["household.sharing.delete"]
        scrollTo(delete, in: app)
        attachScreenshot(app, "household tab bottom")
        delete.tap()

        XCTAssertTrue(app.buttons["Export a backup first"].waitForExistence(timeout: 5))
        attachScreenshot(app, "delete step 1")
        app.buttons["Continue"].tap()

        let finalDelete = app.alerts.buttons["Delete household"]
        XCTAssertTrue(finalDelete.waitForExistence(timeout: 5))
        attachScreenshot(app, "delete step 2")
        finalDelete.tap()

        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        let backToPersonal = NSPredicate(format: "label == %@", "Personal")
        expectation(for: backToPersonal, evaluatedWith: switcher)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["household.sharing.role"].exists)
    }

    @MainActor
    func testTheNewHouseholdSheetOffersAnExport() {
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 10))

        createHousehold(in: app)
        app.buttons["household.new.export"].tap()

        // The document picker in export mode offers "Move" (or "Save" on some iOS builds).
        let picker = app.buttons["Move"].waitForExistence(timeout: 10) || app.buttons["Save"].waitForExistence(timeout: 2)
        attachScreenshot(app, "export from new household")
        XCTAssertTrue(picker, "the .fileExporter sheet did not appear")
    }

    @MainActor
    func testTheDeleteDialogOffersAnExportFirst() {
        let app = XCUIApplication.homassy()
        app.launch()
        app.openTab("Household")
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 10))
        createHousehold(in: app)
        app.buttons["household.new.done"].tap()

        let delete = app.buttons["household.sharing.delete"]
        scrollTo(delete, in: app)
        delete.tap()
        let exportFirst = app.buttons["Export a backup first"]
        XCTAssertTrue(exportFirst.waitForExistence(timeout: 5))
        exportFirst.tap()

        let picker = app.buttons["Move"].waitForExistence(timeout: 10) || app.buttons["Save"].waitForExistence(timeout: 2)
        attachScreenshot(app, "export before delete")
        XCTAssertTrue(picker, "the .fileExporter sheet did not appear")
    }
}
