import XCTest

/// N-04: the shopping Live Activity starts by itself near a store. Under UI tests the app records activities in memory
/// and shows the running one in a hidden probe (`uiTest.liveActivity`: "<title>|<remaining>"); the Lock Screen itself
/// is checked by hand on the iPhone.
final class ShoppingActivityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningTheAppAtAStoreStartsItsActivityWithMergedRows() {
        let app = XCUIApplication.launchedOnShoppingTab(extraArguments: ["-uiTestSeedStoreItems", "-uiTestNearStore"])
        let probe = app.staticTexts["uiTest.liveActivity"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        // Milk 2 l + Milk 1 l is one row, Napkins the other; Soap has no store.
        expectation(for: NSPredicate(format: "label == %@", "Corner Shop|2"), evaluatedWith: probe)
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testAwayFromStoresNothingStarts() {
        let app = XCUIApplication.launchedOnShoppingTab(extraArguments: ["-uiTestSeedStoreItems"])
        let probe = app.staticTexts["uiTest.liveActivity"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        XCTAssertEqual(probe.label, "none")
    }
}
