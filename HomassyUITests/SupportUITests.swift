import XCTest

/// X-03: the "Homassy" section at the bottom of the Household tab (Apple-native option B, user choice
/// 2026-09-26): one "Support development ↗" button and the guide §9.2 copy verbatim as its footer.
/// The button is not tapped: that would load a web page, and UI tests make no network calls.
final class SupportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openHousehold(language: String, householdTab: String) -> XCUIApplication {
        let app = XCUIApplication.homassy(language: language, locale: language)
        app.launch()
        app.openTab(householdTab)
        let button = app.buttons["support.open"]
        var swipes = 0
        while !(button.exists && button.isHittable) && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testEnglishCopyAndButton() {
        let app = openHousehold(language: "en", householdTab: "Household")
        let button = app.buttons["support.open"]
        XCTAssertTrue(button.isHittable)
        XCTAssertTrue(button.label.contains("Support development"), button.label)
        let body = app.staticTexts["support.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.label, "Homassy is free, has no ads and no paid features. If you would like to support its development, you can — it buys nothing and unlocks nothing. Thank you either way.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "support"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHungarianCopyIsVerbatim() {
        let app = openHousehold(language: "hu", householdTab: "Háztartás")
        let body = app.staticTexts["support.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.label, "A Homassy ingyenes, nincs benne hirdetés és nincs fizetős funkció. Ha szeretnéd támogatni a fejlesztést, megteheted — semmit nem vásárolsz vele és semmit nem old fel. Így is, úgy is köszönöm.")
    }

    @MainActor
    func testGermanCopyIsVerbatim() {
        let app = openHousehold(language: "de", householdTab: "Haushalt")
        let body = app.staticTexts["support.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.label, "Homassy ist kostenlos, ohne Werbung und ohne kostenpflichtige Funktionen. Wenn du die Entwicklung unterstützen möchtest, kannst du das tun — du kaufst damit nichts und schaltest nichts frei. Danke so oder so.")
    }
}
