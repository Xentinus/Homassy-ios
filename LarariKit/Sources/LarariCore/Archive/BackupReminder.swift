import Foundation
import Observation

/// The monthly "time for a backup" banner. Silent for the first 14 days, then due 30 days after the later
/// of the last export and the last dismissal.
@MainActor
@Observable
public final class BackupReminder {
    nonisolated public static let reminderIntervalDays = 30
    nonisolated public static let initialGraceDays = 14

    private enum Key {
        static let firstUseAt = "backupReminder.firstUseAt"
        static let lastExportAt = "backupReminder.lastExportAt"
        static let lastDismissedAt = "backupReminder.lastDismissedAt"
    }

    public private(set) var firstUseAt: Date?
    public private(set) var lastExportAt: Date?
    public private(set) var lastDismissedAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        firstUseAt = defaults.object(forKey: Key.firstUseAt) as? Date
        lastExportAt = defaults.object(forKey: Key.lastExportAt) as? Date
        lastDismissedAt = defaults.object(forKey: Key.lastDismissedAt) as? Date
    }

    public func recordFirstUseIfNeeded(now: Date = .now) {
        guard firstUseAt == nil else { return }
        firstUseAt = now
        defaults.set(now, forKey: Key.firstUseAt)
    }

    public func recordExport(now: Date = .now) {
        lastExportAt = now
        defaults.set(now, forKey: Key.lastExportAt)
    }

    public func dismiss(now: Date = .now) {
        lastDismissedAt = now
        defaults.set(now, forKey: Key.lastDismissedAt)
    }

    public func shouldRemind(now: Date = .now) -> Bool {
        Self.shouldRemind(now: now, firstUseAt: firstUseAt, lastExportAt: lastExportAt,
                          lastDismissedAt: lastDismissedAt, calendar: calendar)
    }

    nonisolated public static func shouldRemind(now: Date, firstUseAt: Date?, lastExportAt: Date?,
                                                lastDismissedAt: Date?, calendar: Calendar) -> Bool {
        guard let firstUseAt,
              let graceEnd = calendar.date(byAdding: .day, value: initialGraceDays, to: firstUseAt),
              now >= graceEnd else { return false }
        guard let last = [lastExportAt, lastDismissedAt].compactMap({ $0 }).max() else { return true }
        guard let due = calendar.date(byAdding: .day, value: reminderIntervalDays, to: last) else { return false }
        return now >= due
    }
}
