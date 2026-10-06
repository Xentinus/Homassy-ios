import Foundation
import HomassyCore

/// Where the Inventory and Shopping tabs keep their grouping, the Shopping filter and the last used list. Under UI
/// tests it is a suite wiped once per launch, so one test's choices never leak into the next.
enum TabDefaults {
    static let store: UserDefaults = {
        #if DEBUG
        if UITestHooks.isActive {
            let suite = "uiTest.tabs"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
            // `-uiTestInventoryGrouping location|name|expiry`: start Inventory in that grouping, as if it had been picked before.
            if let grouping = UITestHooks.inventoryGrouping { InventoryPreferences(defaults: defaults).grouping = grouping }
            return defaults
        }
        #endif
        return .standard
    }()
}
