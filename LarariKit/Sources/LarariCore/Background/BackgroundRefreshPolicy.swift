import Foundation

/// When iOS may next wake Larari for a background app refresh (N-01). The summaries fire at 07:00
/// (`NotificationPlanner.fireHour`), so the preferred run is 06:30 local time; the 12 h cap keeps the badge and the
/// store reminders current during the day too. `earliestBeginDate` is a lower bound: iOS picks the actual time.
public enum BackgroundRefreshPolicy {
    public static let taskIdentifier = "app.larari.refresh"
    public static let preferredTime = DateComponents(hour: 6, minute: 30)
    public static let maximumInterval: TimeInterval = 12 * 60 * 60
    public static let minimumInterval: TimeInterval = 15 * 60

    /// The next 06:30 strictly after `now`, but at most 12 h and at least 15 min ahead (real time, so daylight-saving
    /// days are handled by `Calendar`).
    public static func earliestBeginDate(after now: Date, calendar: Calendar) -> Date {
        let ceiling = now.addingTimeInterval(maximumInterval)
        let floor = now.addingTimeInterval(minimumInterval)
        guard let morning = calendar.nextDate(after: now, matching: preferredTime, matchingPolicy: .nextTime,
                                              direction: .forward) else { return ceiling }
        return max(floor, min(morning, ceiling))
    }
}
