import XCTest

extension XCUIApplication {
    /// The app configured for UI tests: English, a fake iCloud account state, an in-memory store,
    /// tips hidden, and (unless `skipIntroduction` is false) the first-launch introduction already seen.
    @MainActor
    static func homassy(accountState: String = "available",
                        skipIntroduction: Bool = true,
                        language: String = "en",
                        locale: String = "en_US",
                        extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                         "-uiTestAccountState", accountState,
                         "-hideTips"]
        if skipIntroduction {
            arguments += ["-hasSeenIntroduction", "YES"]
        }
        app.launchArguments = arguments + extraArguments
        return app
    }
}
