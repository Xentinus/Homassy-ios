import XCTest

/// Product photos: choose (or take) a photo, then crop to a square and rotate before it is stored
/// (user request, 2026-09-24). `-uiTestSamplePhoto` replaces the system photo picker with a generated picture.
@MainActor
final class PhotoEditorUITests: XCTestCase {
    private func openNewProductForm() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.homassy(extraArguments: ["-uiTestSeed", "-uiTestSamplePhoto"])
        app.launch()
        app.openTab("Products")
        let menu = app.navigationBars["Products"].buttons["addMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["addMenu.product"].tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
        return app
    }

    func testChosenPhotoGoesThroughTheEditor() {
        let app = openNewProductForm()
        XCTAssertFalse(app.buttons["product.form.removePhoto"].exists)
        app.buttons["product.form.choosePhoto"].tap()
        let done = app.buttons["photoEditor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["photoEditor.crop"].exists)
        app.buttons["photoEditor.rotate"].tap()
        done.tap()
        XCTAssertTrue(app.buttons["product.form.removePhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["product.form.editPhoto"].exists)

        let name = app.textFields["product.form.name"]
        name.tap()
        name.typeText("Photo Test")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.buttons["product.row.Photo Test"].waitForExistence(timeout: 5))
    }

    func testCancellingTheEditorKeepsNoPhoto() {
        let app = openNewProductForm()
        app.buttons["product.form.choosePhoto"].tap()
        XCTAssertTrue(app.buttons["photoEditor.done"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["product.form.removePhoto"].exists)
    }

    func testCameraButtonOnADeviceWithACamera() {
        let app = openNewProductForm()
        XCTAssertTrue(app.buttons["product.form.takePhoto"].exists, "the test iPhone has a camera")
    }
}
