import XCTest

/// Product photos: every photo action sits in one menu behind the picture; a new photo goes through the square
/// crop and rotate editor before it is stored (user requests, 2026-09-24). `-uiTestSamplePhoto` replaces the system
/// photo picker with a generated picture.
@MainActor
final class PhotoEditorUITests: XCTestCase {
    private func openNewProductForm() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.larari(extraArguments: ["-uiTestSeed", "-uiTestSamplePhoto"])
        app.launch()
        app.openTab("Search")
        let menu = app.navigationBars["Search"].buttons["addMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["addMenu.product"].tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
        return app
    }

    private func openPhotoMenu(_ app: XCUIApplication) {
        let photo = app.buttons["product.form.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(app.buttons["product.form.choosePhoto"].waitForExistence(timeout: 3))
    }

    private func chooseAndCancel(_ app: XCUIApplication) {
        app.buttons["product.form.choosePhoto"].tap()
        XCTAssertTrue(app.buttons["photoEditor.done"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))
    }

    func testChosenPhotoGoesThroughTheEditor() {
        let app = openNewProductForm()
        XCTAssertFalse(app.buttons["product.form.removePhoto"].exists, "no photo actions outside the menu")
        openPhotoMenu(app)
        XCTAssertFalse(app.buttons["product.form.removePhoto"].exists)
        app.buttons["product.form.choosePhoto"].tap()
        let done = app.buttons["photoEditor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["photoEditor.crop"].exists)
        app.buttons["photoEditor.rotate"].tap()
        done.tap()
        XCTAssertTrue(app.textFields["product.form.name"].waitForExistence(timeout: 5))

        openPhotoMenu(app)
        XCTAssertTrue(app.buttons["product.form.removePhoto"].exists)
        app.buttons["product.form.editPhoto"].tap()
        XCTAssertTrue(app.buttons["photoEditor.done"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        let name = app.textFields["product.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Photo Test")
        app.buttons["product.form.save"].tap()
        XCTAssertTrue(app.buttons["product.row.Photo Test"].waitForExistence(timeout: 5))
    }

    func testCancellingTheEditorKeepsNoPhoto() {
        let app = openNewProductForm()
        openPhotoMenu(app)
        chooseAndCancel(app)
        openPhotoMenu(app)
        XCTAssertFalse(app.buttons["product.form.removePhoto"].exists)
        chooseAndCancel(app)
    }

    func testCameraIsOfferedOnADeviceWithACamera() {
        let app = openNewProductForm()
        openPhotoMenu(app)
        XCTAssertTrue(app.buttons["product.form.takePhoto"].exists, "the test iPhone has a camera")
        chooseAndCancel(app)
    }
}
