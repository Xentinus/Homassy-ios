import XCTest

@MainActor
extension XCUIApplication {
    func openTab(_ title: String) {
        let tab = tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(title) missing")
        tab.tap()
    }

    /// P1-07a: the selected space's settings open from "Settings…" in the space menu, not from a tab.
    func openSettings() {
        let switcher = buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "space switcher missing")
        switcher.tap()
        let item = buttons["space.settings"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Settings… missing from the space menu")
        item.tap()
        XCTAssertTrue(buttons["space.settings.done"].waitForExistence(timeout: 5), "the settings sheet did not open")
    }

    func closeSettings() {
        let done = buttons["space.settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the settings sheet did not close")
    }
}
