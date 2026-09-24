import Foundation

/// Ordered least to most severe. `none` means "no expiry date at all".
public enum ExpirationLevel: Int, Comparable, Sendable {
    case none, ok, soon, critical, expired

    public static func < (lhs: ExpirationLevel, rhs: ExpirationLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Counts towards the badge and the "Expiring soon" section.
    public var isAttention: Bool { self >= .soon }
}

/// Sorts more severe first, then the earlier date first; items without a date go last.
public struct ExpirationSortKey: Comparable, Sendable {
    public let level: ExpirationLevel
    public let date: Date?

    public init(level: ExpirationLevel, date: Date?) {
        self.level = level
        self.date = date
    }

    public static func < (lhs: ExpirationSortKey, rhs: ExpirationSortKey) -> Bool {
        if lhs.level != rhs.level { return lhs.level > rhs.level }
        switch (lhs.date, rhs.date) {
        case let (left?, right?): return left < right
        case (.some, .none): return true
        default: return false
        }
    }
}

/// Port of the web app's `useExpirationStatus.ts`.
public enum ExpirationStatus {
    /// Inside this many days an item shows the warning colour.
    public static let soonDays = 14
    /// Inside this many days it shows the error colour.
    public static let criticalDays = 3

    /// Whole calendar days from today until the date in `calendar`'s time zone; negative once past.
    public static func daysUntilExpiration(_ expiresAt: Date?, now: Date, calendar: Calendar) -> Int? {
        guard let expiresAt else { return nil }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: expiresAt)
        return calendar.dateComponents([.day], from: today, to: target).day
    }

    public static func level(expiresAt: Date?, now: Date, calendar: Calendar) -> ExpirationLevel {
        guard let days = daysUntilExpiration(expiresAt, now: now, calendar: calendar) else { return .none }
        if days < 0 { return .expired }
        if days <= criticalDays { return .critical }
        if days <= soonDays { return .soon }
        return .ok
    }

    public static func worstLevel(_ dates: [Date?], now: Date, calendar: Calendar) -> ExpirationLevel {
        dates.map { level(expiresAt: $0, now: now, calendar: calendar) }.max() ?? .none
    }

    public static func sortKey(expiresAt: Date?, now: Date, calendar: Calendar) -> ExpirationSortKey {
        ExpirationSortKey(level: level(expiresAt: expiresAt, now: now, calendar: calendar), date: expiresAt)
    }

    /// "Tomorrow", "In 3 days", "Expired 2 days ago" inside the 14-day window; the date outside it.
    public static func label(expiresAt: Date?, now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let expiresAt, let days = daysUntilExpiration(expiresAt, now: now, calendar: calendar) else { return nil }

        guard abs(days) <= soonDays else {
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale,
                                         calendar: calendar, timeZone: calendar.timeZone)
            return expiresAt.formatted(style)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full

        if days < 0 {
            formatter.formattingContext = .middleOfSentence
            let relative = formatter.localizedString(from: DateComponents(day: days))
            return CoreLocalization.format("expiration.expiredRelative %@", locale: locale, relative)
        }
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: days))
    }
}
