import XCTest

final class HomassyUITests: XCTestCase {
    @MainActor
    func testLaunchShowsRootAndLinksHomassyCore() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let root = app.descendants(matching: .any)["root.placeholder"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "The root placeholder did not appear")
        XCTAssertEqual(root.value as? String, "1.0", "The root must expose HomassyCore.version, which proves the package is linked")
    }
}
