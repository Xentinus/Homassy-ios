import XCTest

@MainActor
extension XCUIApplication {
    /// On the iPhone the tab is in the tab bar. On the iPad (regular width, `sidebarAdaptable`) the sidebar shows it
    /// as a cell, and the floating tab bar (sidebar hidden) as a plain button.
    func openTab(_ title: String) {
        var tab = tabBars.buttons[title]
        if UIDevice.current.userInterfaceIdiom == .pad {
            let cell = cells[title]
            tab = cell.waitForExistence(timeout: 10) ? cell : buttons[title].firstMatch
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(title) missing")
        tab.tap()
    }

    /// P1-07a: the selected space's settings open from "Settings…" in the space menu, not from a tab.
    func openSettings() {
        let switcher = buttons["spaceSwitcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "space switcher missing")
        waitUntilHittable(switcher, timeout: 5)
        switcher.tap()
        var item = buttons["space.settings"].firstMatch
        if !item.waitForExistence(timeout: 3) {
            // openSettings() often runs right after another sheet (member setup, New household) is dismissed;
            // a tap that lands while it's still animating away gets swallowed and the menu never opens. Retry
            // once before treating this as a real failure.
            waitUntilHittable(switcher, timeout: 5)
            switcher.tap()
            item = buttons["space.settings"].firstMatch
        }
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

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !(element.exists && element.isHittable) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
}
