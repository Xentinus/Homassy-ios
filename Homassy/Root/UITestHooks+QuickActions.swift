#if DEBUG
import Foundation
import HomassyCore

extension UITestHooks {
    /// `-uiTestQuickAction <type>`: route as if the Home Screen quick action of that type was chosen (N-02).
    static var quickActionType: String? {
        guard isActive else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiTestQuickAction"), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    /// With `-uiTestSeedShoppingList`, first creates "Weekly" with "Soap" and "Party" with "Napkins" in the Personal
    /// space, and records Weekly as the last used list. Then takes the item of `quickActionType` from the menu
    /// `QuickActionPlanner` would put on the Home Screen now, and routes it; without such an item nothing opens.
    static func runQuickActionIfRequested(services: ServiceContainer) {
        guard let type = quickActionType else { return }
        let lastUsed = LastUsedShoppingList(defaults: TabDefaults.store)
        if contains("-uiTestSeedShoppingList"),
           let personal = (try? services.spaceStore.allSpaces())?.first(where: { $0.kind == .personal }),
           let weekly = try? services.shopping.createList(name: "Weekly", in: personal),
           let party = try? services.shopping.createList(name: "Party", in: personal) {
            _ = try? services.shopping.addItem(to: weekly, customName: "Soap")
            _ = try? services.shopping.addItem(to: party, customName: "Napkins")
            lastUsed.record(weekly.publicId, for: personal.publicId)
        }
        let items = QuickActionPlanner.items(services: services, lastUsed: lastUsed, now: .now, calendar: .current,
                                             locale: Locale(identifier: "en_US"))
        guard let item = items.first(where: { $0.type == type }),
              let destination = QuickAction.destination(type: item.type, userInfo: item.userInfo) else { return }
        AppRouter.shared.open(destination)
    }
}
#endif
