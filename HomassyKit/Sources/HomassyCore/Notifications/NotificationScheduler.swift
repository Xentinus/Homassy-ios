import CoreLocation
import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the scheduler needs, so tests can use a fake.
public protocol NotificationCentering: Sendable {
    func pendingRequestIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func setBadgeCount(_ count: Int) async throws
    /// A location-triggered request (P4-06): fires on every entry into the reminder's circle.
    func addLocation(_ reminder: PlannedStoreReminder) async throws
}

public struct SystemNotificationCenter: NotificationCentering {
    public init() {}

    public func pendingRequestIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "homassy.expiry"
        let trigger = UNCalendarNotificationTrigger(dateMatching: notification.dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setBadgeCount(_ count: Int) async throws {
        try await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    public func addLocation(_ reminder: PlannedStoreReminder) async throws {
        #if os(iOS)
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = "homassy.store"
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: reminder.center.latitude, longitude: reminder.center.longitude),
            radius: reminder.radius, identifier: reminder.identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        #endif
        // macOS (package tests only): location triggers do not exist; the fake center is used there.
    }
}

@MainActor
public final class NotificationScheduler {
    public static let ownPrefixes = [NotificationPlanner.dailyPrefix, NotificationPlanner.weeklyPrefix]
    private let center: any NotificationCentering

    public init(center: any NotificationCentering) {
        self.center = center
    }

    public static let storePrefix = StoreReminderPlanner.identifierPrefix

    /// Removes this feature's pending requests (and nobody else's), then adds `planned` in priority order. Store
    /// reminders (P4-06) never take room from the summaries: they do not count against the budget, and the ones
    /// that would push the total over 64 are removed, highest rank first.
    @discardableResult
    public func reschedule(_ planned: [PlannedNotification]) async -> [PlannedNotification] {
        let pending = await center.pendingRequestIdentifiers()
        let own = pending.filter { id in Self.ownPrefixes.contains { id.hasPrefix($0) } }
        let store = pending.filter { $0.hasPrefix(Self.storePrefix) }
        if !own.isEmpty { await center.removePendingRequests(withIdentifiers: own) }

        let others = pending.count - own.count - store.count
        let budget = max(0, NotificationPlanner.maxPending - others)
        var added: [PlannedNotification] = []
        for notification in planned.prefix(budget) {
            do {
                try await center.add(notification)
                added.append(notification)
            } catch {
                continue                                   // e.g. notifications not authorised; try the rest
            }
        }
        let overflow = others + added.count + store.count - NotificationPlanner.maxPending
        if overflow > 0 {
            let evicted = store.sorted(by: Self.storeRankDescending).prefix(overflow)
            await center.removePendingRequests(withIdentifiers: Array(evicted))
        }
        return added
    }

    /// Replaces every pending store reminder with `planned`, within 20 regions and the room the others leave.
    @discardableResult
    public func rescheduleStoreReminders(_ planned: [PlannedStoreReminder]) async -> [PlannedStoreReminder] {
        let pending = await center.pendingRequestIdentifiers()
        let store = pending.filter { $0.hasPrefix(Self.storePrefix) }
        if !store.isEmpty { await center.removePendingRequests(withIdentifiers: store) }
        let budget = max(0, min(StoreReminderPlanner.maxRegions, NotificationPlanner.maxPending - (pending.count - store.count)))
        var added: [PlannedStoreReminder] = []
        for reminder in planned.prefix(budget) {
            do {
                try await center.addLocation(reminder)
                added.append(reminder)
            } catch {
                break                                      // not authorised: the rest would fail the same way
            }
        }
        return added
    }

    /// "store-<chain>-<rank>": higher rank first, so eviction keeps each chain's nearest branches.
    static func storeRankDescending(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ id: String) -> Int { Int(id.split(separator: "-").last ?? "") ?? 0 }
        return rank(lhs) != rank(rhs) ? rank(lhs) > rank(rhs) : lhs > rhs
    }
}
