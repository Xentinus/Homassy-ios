import CoreData
import Foundation

/// Reads open items across every store in the context (all spaces).
@MainActor
public enum BadgeCounter {
    /// soon + critical + expired: open items expiring before the start of day `soonDays + 1`.
    public static func count(in context: NSManagedObjectContext, now: Date, calendar: Calendar) throws -> Int {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: ExpirationStatus.soonDays + 1, to: today) else { return 0 }
        return try context.countEntities(
            InventoryItem.self,
            where: NSPredicate(format: "isFullyConsumed == NO AND expiresAt != nil AND expiresAt < %@", limit as NSDate))
    }

    /// Open items expiring from today through the horizon plus one week (the last Monday's window).
    public static func snapshots(in context: NSManagedObjectContext, now: Date, calendar: Calendar,
                                 horizonDays: Int = NotificationPlanner.defaultHorizonDays) throws -> [ExpirySnapshot] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: horizonDays + 7, to: today) else { return [] }
        let items = try context.fetchEntities(
            InventoryItem.self,
            where: NSPredicate(format: "isFullyConsumed == NO AND expiresAt >= %@ AND expiresAt < %@",
                               today as NSDate, end as NSDate))
        return items.compactMap { item in
            guard let expiresAt = item.expiresAt, let product = item.product else { return nil }
            return ExpirySnapshot(id: item.publicId, name: product.name, expiresAt: expiresAt,
                                  spaceName: product.space?.name ?? "")
        }
    }
}
