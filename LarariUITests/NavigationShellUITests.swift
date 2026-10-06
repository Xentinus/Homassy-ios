import XCTest

final class NavigationShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// P1-07a: two tabs and the Search tab; Products and Household are gone (user decision 2026-09-26).
    @MainActor
    func testTwoTabsAndSearchExist() throws {
        let app = XCUIApplication.larari()
        app.launch()

        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        for title in ["Inventory", "Shopping", "Search"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "Missing tab \(title)")
        }
        for title in ["Products", "Household"] {
            XCTAssertFalse(app.tabBars.buttons[title].exists, "Tab \(title) should be gone")
        }
    }

    @MainActor
    func testSwitchingTabsChangesTheScreen() throws {
        let app = XCUIApplication.larari()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        app.openTab("Shopping")
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 5))
        app.openTab("Search")
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRotationKeepsTheSelectedTab() throws {
        let app = XCUIApplication.larari()
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
    func testSpaceSwitcherListsPersonalNewHouseholdAndSettings() throws {
        let app = XCUIApplication.larari()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        let switcher = app.buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertEqual(switcher.label, "Personal")
        switcher.tap()

        XCTAssertTrue(app.buttons["Personal"].firstMatch.waitForExistence(timeout: 5))
        let newHousehold = app.buttons["New household"].firstMatch
        XCTAssertTrue(newHousehold.exists)
        XCTAssertTrue(newHousehold.isEnabled)      // live since P5-01
        XCTAssertTrue(app.buttons["space.settings"].firstMatch.exists)
    }

    /// The Home app pattern: "Settings…" in the space menu opens the space's settings as a sheet, Done closes it.
    @MainActor
    func testSettingsOpenFromTheSpaceMenuOnEveryTab() throws {
        let app = XCUIApplication.larari()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        for tab in ["Inventory", "Shopping", "Search"] {
            app.openTab(tab)
            app.openSettings()
            XCTAssertTrue(app.navigationBars["Personal"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["household.storageLocations"].exists)
            app.closeSettings()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "back on search"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Shopping's `+` menu is live since P4-03.
    @MainActor
    func testShoppingAddMenuIsLive() throws {
        let app = XCUIApplication.larari()
        app.launch()
        app.openTab("Shopping")
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 10))
        let addMenu = app.navigationBars["Shopping"].buttons["addMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let newList = app.buttons["New shopping list"].firstMatch
        XCTAssertTrue(newList.waitForExistence(timeout: 5))
        XCTAssertTrue(newList.isEnabled)
    }

    /// Inventory's `+` menu is live since P2-08.
    @MainActor
    func testInventoryAddMenuIsLive() throws {
        let app = XCUIApplication.larari()
        app.launch()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))
        app.navigationBars["Inventory"].buttons["addMenu"].tap()
        let addItem = app.buttons["addMenu.stock"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        XCTAssertTrue(addItem.isEnabled)
    }

    @MainActor
    func testIPadShowsAllSectionsInRegularWidth() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = XCUIApplication.larari()
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10))

        for title in ["Inventory", "Shopping"] {
            let item = app.buttons[title].firstMatch
            XCTAssertTrue(item.exists, "Missing section \(title)")
            XCTAssertTrue(item.isHittable, "Section \(title) not reachable")
        }
        app.openSettings()
        XCTAssertTrue(app.navigationBars["Personal"].waitForExistence(timeout: 5))
    }
}
