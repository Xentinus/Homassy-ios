import Foundation

/// Where the Inventory and Shopping tabs keep their grouping, the Shopping filter and the last used list. Under UI
/// tests it is a suite wiped once per launch, so one test's choices never leak into the next.
enum TabDefaults {
    static let store: UserDefaults = {
        #if DEBUG
        if UITestHooks.isActive {
            let suite = "uiTest.tabs"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite) ?? .standard
        }
        #endif
        return .standard
    }()
}
