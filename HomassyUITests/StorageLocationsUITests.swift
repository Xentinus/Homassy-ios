import XCTest

@MainActor
final class StorageLocationsUITests: XCTestCase {
    private func openStorageLocations() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed"])
        app.launch()
        app.openSettings()
        let link = app.buttons["household.storageLocations"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        return app
    }

    func testShowsSeededLocationsInOrder() {
        let app = openStorageLocations()
        let fridge = app.buttons["storageLocation.row.Fridge"]
        let pantry = app.buttons["storageLocation.row.Pantry"]
        let freezer = app.buttons["storageLocation.row.Freezer"]
        XCTAssertTrue(fridge.waitForExistence(timeout: 5))
        XCTAssertTrue(pantry.exists && freezer.exists)
        XCTAssertLessThan(fridge.frame.minY, pantry.frame.minY)
        XCTAssertLessThan(pantry.frame.minY, freezer.frame.minY)
    }

    func testAddLocation() {
        let app = openStorageLocations()
        app.buttons["storageLocations.add"].tap()
        let name = app.textFields["storageLocation.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["storageLocation.save"].isEnabled)
        name.tap()
        name.typeText("Cellar")
        app.buttons["color.green"].tap()
        let freezer = app.switches["storageLocation.freezer"]
        freezer.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(freezer.value as? String, "1")
        app.buttons["storageLocation.save"].tap()
        XCTAssertTrue(app.buttons["storageLocation.row.Cellar"].waitForExistence(timeout: 5))
    }

    func testCustomColorPickerIsOffered() {
        let app = openStorageLocations()
        app.buttons["storageLocations.add"].tap()
        let custom = app.descendants(matching: .any)["color.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.isHittable)
    }

    func testSwipeDeleteAndUndo() {
        let app = openStorageLocations()
        let pantry = app.buttons["storageLocation.row.Pantry"]
        XCTAssertTrue(pantry.waitForExistence(timeout: 5))
        pantry.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(pantry.waitForNonExistence(timeout: 3))
        // The settings sheet and the tab behind it each keep their own undo overlay (P1-07a): the sheet's is
        // the hittable one, so wait for that rather than an arbitrary match of the ambiguous identifier.
        let undoCandidates = app.buttons.matching(identifier: "undoToast.undo")
        let deadline = Date().addingTimeInterval(3)
        while undoCandidates.allElementsBoundByIndex.first(where: \.isHittable) == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let undo = undoCandidates.allElementsBoundByIndex.first(where: \.isHittable) ?? undoCandidates.firstMatch
        XCTAssertTrue(undo.exists && undo.isHittable, "no hittable undo button found")
        undo.tap()
        XCTAssertTrue(pantry.waitForExistence(timeout: 3))
    }

    func testSwipeDeleteCommitsAfterWindow() {
        let app = openStorageLocations()
        let freezer = app.buttons["storageLocation.row.Freezer"]
        XCTAssertTrue(freezer.waitForExistence(timeout: 5))
        freezer.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["undoToast.undo"].waitForNonExistence(timeout: 8))
        XCTAssertFalse(freezer.exists)
    }
}
