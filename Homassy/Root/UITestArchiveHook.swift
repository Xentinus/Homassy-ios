#if DEBUG
import Foundation
import HomassyCore

/// `-uiTestImportFixture`: writes ArchiveSamples.sampleV1 as a .homassy file at launch and opens it,
/// exactly as if it had arrived through Files or AirDrop.
enum UITestArchiveHook {
    static let argument = "-uiTestImportFixture"

    static func fixtureURLIfRequested() -> URL? {
        guard UITestHooks.isActive, UITestHooks.contains(argument) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "sample-v1.homassy")
        do {
            try ArchivePackage.write(ArchiveSamples.sampleV1, images: [:], to: url)
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
