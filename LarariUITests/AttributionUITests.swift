import XCTest

/// P5-04: a card changed by someone else shows a ring in their colour and "Name · now" in its own text.
/// Locally nobody else changes anything, so `-uiTestAttribution` simulates a change to Milk.
final class AttributionUITests: XCTestCase {
    @MainActor
    func testACardChangedByAnotherMemberShowsWhoChangedIt() {
        continueAfterFailure = false
        let app = XCUIApplication.larari(extraArguments: ["-uiTestSeed", "-uiTestAttribution"])
        app.launch()
        app.openTab("Search")

        // The caption is part of the card's combined label, which VoiceOver reads too.
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "New member · now")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the attribution caption did not show")
        XCTAssertTrue(card.label.contains("Milk"), card.label)
        var swipes = 0
        while !card.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "attribution"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
