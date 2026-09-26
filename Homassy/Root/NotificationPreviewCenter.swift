#if DEBUG
import Foundation
import HomassyCore

/// `-notificationPreview` (DEBUG, P2-10 manual check): schedules the real plan as usual, and also a "preview-" copy of
/// the first two daily summaries, the first weekly one and the first store reminder, firing 1, 2, 3 and 4
/// minutes from now. The real 07:00 requests stay untouched, and the
/// copies are foreign to `NotificationScheduler` (no daily-/weekly- prefix), so they are never removed early.
/// Launch it with `xcrun devicectl device process launch --device <id> com.homassy.app -notificationPreview`.
nonisolated struct NotificationPreviewCenter: NotificationCentering {
    static let argument = "-notificationPreview"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    private let system = SystemNotificationCenter()
    private let counter = PreviewCounter()

    func pendingRequestIdentifiers() async -> [String] { await system.pendingRequestIdentifiers() }

    func add(_ notification: PlannedNotification) async throws {
        try await system.add(notification)
        let isWeekly = notification.identifier.hasPrefix(NotificationPlanner.weeklyPrefix)
        guard let index = await counter.next(weekly: isWeekly) else { return }
        let fire = Date.now.addingTimeInterval(Double(index + 1) * 60)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        try await system.add(PlannedNotification(identifier: "preview-" + notification.identifier, fireDate: fire,
                                                 dateComponents: components, title: notification.title,
                                                 body: notification.body))
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        await system.removePendingRequests(withIdentifiers: identifiers)
    }

    func setBadgeCount(_ count: Int) async throws { try await system.setBadgeCount(count) }

    func addLocation(_ reminder: PlannedStoreReminder) async throws {
        try await system.addLocation(reminder)
        guard await counter.nextStore() else { return }
        let fire = Date.now.addingTimeInterval(4 * 60)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        try await system.add(PlannedNotification(identifier: "preview-" + reminder.identifier, fireDate: fire,
                                                 dateComponents: components, title: reminder.title, body: reminder.body))
    }
}

/// Hands out the preview slots: minutes 1 and 2 for the first two dailies, minute 3 for the first weekly.
/// Each slot is used once per launch, so later refreshes do not reschedule the previews.
private actor PreviewCounter {
    private var dailies = 0
    private var weeklyDone = false

    private var storeDone = false

    func nextStore() -> Bool {
        guard !storeDone else { return false }
        storeDone = true
        return true
    }

    func next(weekly: Bool) -> Int? {
        if weekly {
            guard !weeklyDone else { return nil }
            weeklyDone = true
            return 2
        }
        guard dailies < 2 else { return nil }
        defer { dailies += 1 }
        return dailies
    }
}
#endif
