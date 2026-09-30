import HomassyCore
import HomassyShared
import SwiftUI

@main
struct HomassyApp: App {
    /// Only routes scenes to `SceneDelegate`, which receives CloudKit share invitations.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel.shared
    // App-wide view state for archives; not domain services, so they stay out of ServiceContainer.
    @State private var archiveRouter = ArchiveImportRouter()
    @State private var backupReminder = HomassyApp.makeBackupReminder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(archiveRouter)
                .environment(backupReminder)
                .onOpenURL { url in
                    if let link = HomassyDeepLink(url: url) {
                        AppRouter.shared.open(AppDestination(link))      // Live Activity and widget taps (N-04, N-05)
                    } else {
                        archiveRouter.open(url)
                    }
                }
                #if DEBUG
                .task {
                    if let url = UITestArchiveHook.fixtureURLIfRequested() { archiveRouter.open(url) }
                }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Pending changes are saved rather than lost if the app is suspended inside the undo window.
            // A failure is recorded in `lastError` and shown when the app returns.
            if phase == .background {
                try? appModel.undoQueue.commitAll()
                BackgroundRefresh.submit()      // N-01: the next wake-up, counted from now
                QuickActions.update(appModel)   // N-02: the Home Screen menu shows the last list and the count
            }
        }
    }

    private static func makeBackupReminder() -> BackupReminder {
        #if DEBUG
        if let defaults = UITestArchiveHook.backupReminderDefaults() { return BackupReminder(defaults: defaults) }
        #endif
        return BackupReminder(defaults: AppModel.appDefaults)
    }
}
