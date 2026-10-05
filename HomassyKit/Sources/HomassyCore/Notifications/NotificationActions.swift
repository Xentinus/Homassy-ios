import Foundation
import UserNotifications

/// Notification categories and what a tap means (N-02). Expiry summaries (`daily-`, `weekly-`) and store reminders
/// (`store-`) each have a category; the DEBUG `preview-` copies behave like their originals. Decision 2A
/// (2026-09-29): the categories have no buttons, a tap opens where the items are (P4-06 choice A).
public enum NotificationActions {
    public static let expiryCategory = "homassy.expiry"
    public static let storeCategory = "homassy.store"

    public static func category(forIdentifier identifier: String) -> String? {
        let id = identifier.hasPrefix("preview-") ? String(identifier.dropFirst("preview-".count)) : identifier
        if id.hasPrefix(StoreReminderPlanner.identifierPrefix) { return storeCategory }
        if id.hasPrefix(NotificationPlanner.dailyPrefix) || id.hasPrefix(NotificationPlanner.weeklyPrefix) {
            return expiryCategory
        }
        return nil
    }

    /// Expiry summaries open Inventory grouped by expiry, store reminders Shopping, on the space in `userInfo`. Nil for a dismissal
    /// or a notification that is not ours.
    public static func destination(actionIdentifier: String, requestIdentifier: String,
                                   spaceID: UUID?) -> AppDestination? {
        guard actionIdentifier != UNNotificationDismissActionIdentifier,
              let category = category(forIdentifier: requestIdentifier) else { return nil }
        return category == storeCategory ? .shopping(spaceID: spaceID) : .inventoryExpiring(spaceID: spaceID)
    }

    /// The space `SystemNotificationCenter` put in `userInfo`. Pure, so the delegate can call it on its own thread.
    public static func spaceID(in userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[SystemNotificationCenter.spaceIDKey] as? String).flatMap(UUID.init(uuidString:))
    }

    /// Registered once at launch, so a later version can add buttons without rescheduling the requests.
    public static func categories() -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(identifier: expiryCategory, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: storeCategory, actions: [], intentIdentifiers: [], options: []),
        ]
    }
}
