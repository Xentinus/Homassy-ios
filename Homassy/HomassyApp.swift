import HomassyCore
import SwiftUI

@main
struct HomassyApp: App {
    @State private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
