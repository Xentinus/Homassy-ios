import XCTest

@MainActor
extension XCUIApplication {
    func openTab(_ title: String) {
        let tab = tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(title) missing")
        tab.tap()
    }
}
