import CoreData
import Foundation

/// Home Screen quick action types (N-02). The raw value is `UIApplicationShortcutItem.type`.
public enum QuickAction: String, CaseIterable, Sendable {
    case scanBarcode = "app.larari.quick.scan"
    case addToList = "app.larari.quick.addToList"
    case openList = "app.larari.quick.openList"
    case expiringSoon = "app.larari.quick.expiring"

    public static let spaceIDKey = "spaceID"
    public static let listIDKey = "listID"

    /// Nil for a type this version does not know (an item left over from another build).
    public static func destination(type: String, userInfo: [String: String]) -> AppDestination? {
        guard let action = QuickAction(rawValue: type) else { return nil }
        let space = userInfo[spaceIDKey].flatMap(UUID.init(uuidString:))
        let list = userInfo[listIDKey].flatMap(UUID.init(uuidString:))
        switch action {
        case .scanBarcode:
            return .scanBarcode
        case .expiringSoon:
            return .inventoryExpiring(spaceID: space)
        case .openList:
            guard let space, let list else { return .shopping(spaceID: space) }
            return .shoppingList(spaceID: space, listID: list)
        case .addToList:
            guard let space, let list else { return .shopping(spaceID: space) }
            return .addToShoppingList(spaceID: space, listID: list)
        }
    }
}

/// One Home Screen menu entry, ready for `UIApplicationShortcutItem` (SF Symbol name for the icon).
public struct QuickActionItem: Equatable, Sendable {
    public let type: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let userInfo: [String: String]
}

/// Builds the dynamic Home Screen menu (N-02 decision 1A). The order is the order iOS shows.
@MainActor
public enum QuickActionPlanner {
    public static let maxItems = 4

    public static func items(lastList: ShoppingListReference?, listName: String, expiringCount: Int,
                             locale: Locale) -> [QuickActionItem] {
        func text(_ key: String) -> String { CoreLocalization.string(key, locale: locale) }
        var items = [QuickActionItem(type: QuickAction.scanBarcode.rawValue, title: text("quickAction.scan"),
                                     subtitle: nil, systemImage: "barcode.viewfinder", userInfo: [:])]
        if let lastList {
            let info = [QuickAction.spaceIDKey: lastList.spaceID.uuidString, QuickAction.listIDKey: lastList.listID.uuidString]
            items.append(QuickActionItem(type: QuickAction.addToList.rawValue, title: text("quickAction.addToList"),
                                         subtitle: listName, systemImage: "cart.badge.plus", userInfo: info))
            items.append(QuickActionItem(type: QuickAction.openList.rawValue, title: listName,
                                         subtitle: text("quickAction.openList.subtitle"), systemImage: "list.bullet",
                                         userInfo: info))
        }
        let count = expiringCount > 0
            ? CoreLocalization.format("quickAction.expiring.count %lld", locale: locale, expiringCount) : nil
        items.append(QuickActionItem(type: QuickAction.expiringSoon.rawValue, title: text("quickAction.expiring"),
                                     subtitle: count, systemImage: "clock.badge.exclamationmark", userInfo: [:]))
        return Array(items.prefix(maxItems))
    }

    /// The menu from the store: the last used list (any space) if it still exists, and the badge count (all spaces).
    public static func items(services: ServiceContainer, lastUsed: LastUsedShoppingList, now: Date, calendar: Calendar,
                             locale: Locale) -> [QuickActionItem] {
        let reference = lastUsed.lastReference
        let list = reference.flatMap { services.shoppingList($0) }
        let count = (try? BadgeCounter.count(in: services.context, now: now, calendar: calendar)) ?? 0
        return items(lastList: list == nil ? nil : reference, listName: list?.name ?? "", expiringCount: count,
                     locale: locale)
    }
}
