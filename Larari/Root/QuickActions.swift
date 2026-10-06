import Foundation
import LarariCore
import UIKit

/// Home Screen quick actions (N-02, decision 1A). The menu is rebuilt from `QuickActionPlanner` whenever the scene
/// goes to the background; a chosen item routes through `AppRouter`.
enum QuickActions {
    /// The app's language for strings built outside SwiftUI (the menu items).
    static var appLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    static func update(_ app: AppModel) {
        #if DEBUG
        if UITestHooks.isActive { return }          // keep the test iPhone's real menu
        #endif
        guard let services = app.services else { return }
        let items = QuickActionPlanner.items(services: services,
                                             lastUsed: LastUsedShoppingList(defaults: TabDefaults.store),
                                             now: .now, calendar: .current, locale: appLocale)
        UIApplication.shared.shortcutItems = items.map { item in
            UIApplicationShortcutItem(type: item.type, localizedTitle: item.title, localizedSubtitle: item.subtitle,
                                      icon: UIApplicationShortcutIcon(systemImageName: item.systemImage),
                                      userInfo: item.userInfo.mapValues { $0 as NSString })
        }
    }

    /// True when the item was one of ours (the system wants to know).
    static func handle(_ shortcut: UIApplicationShortcutItem) -> Bool {
        let info = (shortcut.userInfo ?? [:]).compactMapValues { $0 as? String }
        guard let destination = QuickAction.destination(type: shortcut.type, userInfo: info) else { return false }
        AppRouter.shared.open(destination)
        return true
    }
}
