#if DEBUG
import Foundation
import LarariCore

/// `-uiTestImportFixture`: writes ArchiveSamples.sampleV1 as a .larari file at launch and opens it,
/// exactly as if it had arrived through Files or AirDrop.
enum UITestArchiveHook {
    static let argument = "-uiTestImportFixture"
    /// Same file, but the household belongs to someone else, so its members are withheld (P5-02a).
    static let foreignArgument = "-uiTestImportFixtureForeign"

    static func fixtureURLIfRequested() -> URL? {
        guard UITestHooks.isActive else { return nil }
        let foreign = UITestHooks.contains(foreignArgument)
        guard foreign || UITestHooks.contains(argument) else { return nil }
        var contents = ArchiveSamples.sampleV1
        // By default the UI-test user owned the household, so every member can be imported.
        if !foreign { contents.data.space.createdBy = UITestHooks.userRecordName }
        let url = FileManager.default.temporaryDirectory.appending(path: "sample-v1.larari")
        do {
            try ArchivePackage.write(contents, images: [:], to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Under UI tests the reminder starts from nothing on every launch, so the banner never shows up
    /// uninvited on the test iPhone.
    static func backupReminderDefaults() -> UserDefaults? {
        guard UITestHooks.isActive else { return nil }
        let suite = "uiTest.backupReminder"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)
    }
}
#endif
