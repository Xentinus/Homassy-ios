import Foundation

/// Where the Shopping tab keeps its filter, grouping and last used list. Under UI tests it is a suite wiped once
/// per launch, so one test's filter or grouping never leaks into the next.
enum ShoppingDefaults {
    static let store: UserDefaults = {
        #if DEBUG
        if UITestHooks.isActive {
            let suite = "uiTest.shoppingHome"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite) ?? .standard
        }
        #endif
        return .standard
    }()
}
