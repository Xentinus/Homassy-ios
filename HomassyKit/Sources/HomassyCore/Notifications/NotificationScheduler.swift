import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the scheduler needs, so tests can use a fake.
public protocol NotificationCentering: Sendable {
    func pendingRequestIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func setBadgeCount(_ count: Int) async throws
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
}

@MainActor
public final class NotificationScheduler {
    public static let ownPrefixes = [NotificationPlanner.dailyPrefix, NotificationPlanner.weeklyPrefix]
    private let center: any NotificationCentering

    public init(center: any NotificationCentering) {
        self.center = center
    }

    /// Removes this feature's pending requests (and nobody else's), then adds `planned` in priority
    /// order until the system-wide limit of 64 pending requests is reached. Returns what was added.
    @discardableResult
    public func reschedule(_ planned: [PlannedNotification]) async -> [PlannedNotification] {
        let pending = await center.pendingRequestIdentifiers()
        let own = pending.filter { id in Self.ownPrefixes.contains { id.hasPrefix($0) } }
        if !own.isEmpty { await center.removePendingRequests(withIdentifiers: own) }

        let budget = max(0, NotificationPlanner.maxPending - (pending.count - own.count))
        var added: [PlannedNotification] = []
        for notification in planned.prefix(budget) {
            do {
                try await center.add(notification)
                added.append(notification)
            } catch {
                continue                                   // e.g. notifications not authorised; try the rest
            }
        }
        return added
    }
}
