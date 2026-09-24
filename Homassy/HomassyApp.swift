import HomassyCore
import SwiftUI

@main
struct HomassyApp: App {
    @State private var appModel = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pending changes are saved rather than lost if the app is suspended inside the undo window.
            // A failure is recorded in `lastError` and shown when the app returns.
            if phase == .background { try? appModel.undoQueue.commitAll() }
        }
    }
}
