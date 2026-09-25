import HomassyCore
import SwiftUI

@main
struct HomassyApp: App {
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
                .onOpenURL { url in archiveRouter.open(url) }
                #if DEBUG
                .task {
                    if let url = UITestArchiveHook.fixtureURLIfRequested() { archiveRouter.open(url) }
                }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Pending changes are saved rather than lost if the app is suspended inside the undo window.
            // A failure is recorded in `lastError` and shown when the app returns.
            if phase == .background { try? appModel.undoQueue.commitAll() }
        }
    }

    private static func makeBackupReminder() -> BackupReminder {
        #if DEBUG
        if let defaults = UITestArchiveHook.backupReminderDefaults() { return BackupReminder(defaults: defaults) }
        #endif
        return BackupReminder(defaults: AppModel.appDefaults)
    }
}
