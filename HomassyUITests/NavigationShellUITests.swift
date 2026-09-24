import XCTest

final class NavigationShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourTabsAndSearchExist() throws {
        let app = XCUIApplication.homassy()
        app.launch()

        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        for title in ["Inventory", "Shopping", "Products", "Household", "Search"] {
            XCTAssertTrue(app.buttons[title].firstMatch.exists, "Missing tab \(title)")
        }
    }

    @MainActor
    func testSwitchingTabsChangesTheScreen() throws {
        let app = XCUIApplication.homassy()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        app.buttons["Products"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Products"].waitForExistence(timeout: 5))
        app.buttons["Household"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRotationKeepsTheSelectedTab() throws {
        let app = XCUIApplication.homassy()
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        app.buttons["Shopping"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Shopping"].firstMatch.isSelected)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSpaceSwitcherListsPersonalAndDisabledNewHousehold() throws {
        let app = XCUIApplication.homassy()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertEqual(switcher.label, "Personal")
        switcher.tap()

        XCTAssertTrue(app.buttons["Personal"].firstMatch.waitForExistence(timeout: 5))
        let newHousehold = app.buttons["New household"].firstMatch
        XCTAssertTrue(newHousehold.exists)
        XCTAssertFalse(newHousehold.isEnabled)
    }

    @MainActor
    func testAddMenuExistsWithPlaceholderItems() throws {
        let app = XCUIApplication.homassy()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        let addMenu = app.buttons["addMenu"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let addItem = app.buttons["Add item"].firstMatch
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        XCTAssertFalse(addItem.isEnabled)
    }

    @MainActor
    func testIPadShowsAllSectionsInRegularWidth() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = XCUIApplication.homassy()
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        for title in ["Inventory", "Shopping", "Products", "Household"] {
            let item = app.buttons[title].firstMatch
            XCTAssertTrue(item.exists, "Missing section \(title)")
            XCTAssertTrue(item.isHittable, "Section \(title) not reachable")
        }
        app.buttons["Household"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 5))
    }
}
