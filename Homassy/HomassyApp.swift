import HomassyCore
import SwiftUI

@main
struct HomassyApp: App {
    /// Routes every window's scene to `SceneDelegate`, which receives CloudKit share invitations.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel.shared
    // App-wide view state for archives; not a domain service, so it stays out of ServiceContainer. The import router
    // is per window (`SceneRoot`, N-03).
    @State private var backupReminder = HomassyApp.makeBackupReminder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // The main window: tabs and the space menu. On iPad there can be several (N-03), each with its own space,
        // undo toast and import.
        WindowGroup {
            SceneRoot()
                .environment(appModel)
                .environment(backupReminder)
        }
        .onChange(of: scenePhase) { _, phase in
            // The whole app is being suspended: save every window's pending changes rather than lose them. Each
            // window also saves its own when it alone leaves the screen (SceneRoot). A failure is recorded in the
            // window's `lastError` and shown when the app returns.
            if phase == .background {
                try? appModel.undoQueues.commitAll()
                BackgroundRefresh.submit()      // N-01: the next wake-up, counted from now
                QuickActions.update(appModel)   // N-02: the Home Screen menu shows the last list and the count
            }
        }

        // A window for one shopping list or one product (N-03), opened with "Open in New Window" or by dragging a
        // card to the screen edge. SwiftUI restores it with its value, and brings an open window with the same value
        // forward instead of opening a second.
        WindowGroup(for: WindowRoute.self) { $route in
            SceneRoot(route: $route)
                .environment(appModel)
                .environment(backupReminder)
        }
        .handlesExternalEvents(matching: [WindowRoute.activityType])
    }

    private static func makeBackupReminder() -> BackupReminder {
        #if DEBUG
        if let defaults = UITestArchiveHook.backupReminderDefaults() { return BackupReminder(defaults: defaults) }
        #endif
        return BackupReminder(defaults: AppModel.appDefaults)
    }
}
