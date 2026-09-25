import XCTest

final class ArchiveUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed"] + extra)
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testExportOpensTheSystemExporter() {
        let app = launch()
        app.openTab("Household")
        let export = app.buttons["archive.export"]
        var swipes = 0
        while !(export.exists && export.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(export.isHittable)
        export.tap()

        // The document picker in export mode offers "Move" (or "Save" on some iOS builds).
        let picker = app.buttons["Move"].waitForExistence(timeout: 10) || app.buttons["Save"].waitForExistence(timeout: 2)
        attachScreenshot(app, "exporter")
        XCTAssertTrue(picker, "the .fileExporter sheet did not appear")
    }

    /// P5-02a: someone else's household brings no other members; the footer says why.
    @MainActor
    func testSomeoneElsesArchiveWithholdsMembers() {
        let app = launch(["-uiTestImportFixtureForeign"])

        let products = app.staticTexts["import.count.products"]
        XCTAssertTrue(products.waitForExistence(timeout: 15))
        XCTAssertEqual(products.label, "2")
        let members = app.staticTexts["import.count.members"]
        scrollTo(members, in: app)
        XCTAssertEqual(members.label, "0")
        XCTAssertFalse(app.switches["import.group.members"].isEnabled)
        let withheld = app.staticTexts["import.membersWithheld"]
        scrollTo(withheld, in: app)
        XCTAssertTrue(withheld.label.contains("Members left out: 2"))
        attachScreenshot(app, "members withheld")
    }

    @MainActor
    func testOpenedArchiveShowsPreviewCountsAndImports() {
        let app = launch(["-uiTestImportFixture"])

        let products = app.staticTexts["import.count.products"]
        XCTAssertTrue(products.waitForExistence(timeout: 15))
        attachScreenshot(app, "import preview")
        XCTAssertEqual(products.label, "2")
        XCTAssertEqual(app.staticTexts["import.count.storageLocations"].label, "1")
        XCTAssertEqual(app.staticTexts["import.count.inventoryItems"].label, "2")
        let members = app.staticTexts["import.count.members"]
        scrollTo(members, in: app)
        XCTAssertEqual(members.label, "2")

        let name = app.textFields["import.newSpaceName"]
        var swipes = 0
        while !name.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertEqual(name.value as? String, "Otthon")

        app.buttons["import.confirm"].tap()
        XCTAssertTrue(app.staticTexts["import.done"].waitForExistence(timeout: 10))
        attachScreenshot(app, "import done")
        app.buttons["import.close"].tap()
        XCTAssertFalse(app.staticTexts["import.done"].exists)

        // The imported household is selected.
        let switcher = app.buttons["spaceSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertTrue(switcher.label.contains("Otthon"), "switcher shows \(switcher.label)")
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, up: Bool = false) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 6 {
            if up { app.swipeDown() } else { app.swipeUp() }
            swipes += 1
        }
    }

    @MainActor
    func testImportingOnlyChosenProducts() {
        let app = launch(["-uiTestImportFixture"])
        XCTAssertTrue(app.staticTexts["import.count.products"].waitForExistence(timeout: 15))

        // Everything but products off.
        for group in ["stock", "storageLocations", "shoppingLocations", "shoppingLists", "members"] {
            let toggle = app.switches["import.group.\(group)"]
            scrollTo(toggle, in: app)
            XCTAssertEqual(toggle.value as? String, "1", group)
            toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
            XCTAssertEqual(toggle.value as? String, "0", "\(group) did not turn off")
        }

        // Keep only Tej.
        let pick = app.buttons["import.pick.products"]
        scrollTo(pick, in: app, up: true)
        pick.tap()
        let flour = app.buttons["import.record.Liszt"]
        XCTAssertTrue(flour.waitForExistence(timeout: 5))
        flour.tap()
        attachScreenshot(app, "product picker")
        XCTAssertFalse(flour.isSelected)
        XCTAssertTrue(app.buttons["import.record.Tej"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertEqual(app.staticTexts["import.count.products"].label, "1")
        let members = app.staticTexts["import.count.members"]
        scrollTo(members, in: app)
        XCTAssertEqual(members.label, "0")
        attachScreenshot(app, "selective preview")

        app.buttons["import.confirm"].tap()
        XCTAssertTrue(app.staticTexts["import.done"].waitForExistence(timeout: 10))
        app.buttons["import.close"].tap()

        app.openTab("Products")
        XCTAssertTrue(app.descendants(matching: .any)["product.row.Tej"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["product.row.Liszt"].exists)
    }

    @MainActor
    func testPickingMembers() {
        let app = launch(["-uiTestImportFixture"])
        XCTAssertTrue(app.staticTexts["import.count.products"].waitForExistence(timeout: 15))
        let pick = app.buttons["import.pick.members"]
        scrollTo(pick, in: app)
        pick.tap()
        let bela = app.buttons["import.record.Béla"]
        XCTAssertTrue(bela.waitForExistence(timeout: 5))
        bela.tap()
        XCTAssertFalse(bela.isSelected)
        attachScreenshot(app, "member picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let members = app.staticTexts["import.count.members"]
        scrollTo(members, in: app)
        XCTAssertEqual(members.label, "1")
        XCTAssertEqual(app.switches["import.group.members"].value as? String, "1")
    }
}
