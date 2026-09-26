import Foundation

public struct ExpirySnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let expiresAt: Date
    public let spaceName: String

    public init(id: UUID, name: String, expiresAt: Date, spaceName: String) {
        self.id = id
        self.name = name
        self.expiresAt = expiresAt
        self.spaceName = spaceName
    }
}

public struct PlannedNotification: Sendable, Equatable {
    public let identifier: String
    public let fireDate: Date
    public let dateComponents: DateComponents
    public let title: String
    public let body: String

    public init(identifier: String, fireDate: Date, dateComponents: DateComponents, title: String, body: String) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.dateComponents = dateComponents
        self.title = title
        self.body = body
    }
}

/// Pure: expiry snapshots in, summary notifications out (spec §6.5). Never per item, never over 64.
public enum NotificationPlanner {
    public static let maxPending = 64
    public static let defaultHorizonDays = 14
    public static let fireHour = 7
    public static let dailyPrefix = "daily-"
    public static let weeklyPrefix = "weekly-"
    public static let namesShown = 3

    public static func plan(items: [ExpirySnapshot], now: Date, calendar: Calendar, locale: Locale,
                            horizonDays: Int = defaultHorizonDays) -> [PlannedNotification] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.expiresAt) }
        func day(_ offset: Int, from start: Date = today) -> Date? { calendar.date(byAdding: .day, value: offset, to: start) }

        var daily: [PlannedNotification] = []
        var weekly: [PlannedNotification] = []
        for offset in 0..<max(horizonDays, 0) {
            guard let date = day(offset),
                  let fire = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: date),
                  fire > now else { continue }

            let todays = byDay[date] ?? []
            let tomorrows = day(1, from: date).flatMap { byDay[$0] } ?? []
            if !todays.isEmpty || !tomorrows.isEmpty {
                let key = switch (todays.isEmpty, tomorrows.isEmpty) {
                case (false, false): "notification.daily.todayAndTomorrow %lld"
                case (false, true): "notification.daily.today %lld"
                default: "notification.daily.tomorrow %lld"
                }
                daily.append(notification(prefix: dailyPrefix, day: date, fire: fire, calendar: calendar, locale: locale,
                                          title: "notification.daily.title", countKey: key, items: todays + tomorrows))
            }

            if calendar.component(.weekday, from: date) == 2 {                 // Monday in the Gregorian calendar
                let week = (0..<7).compactMap { day($0, from: date) }.flatMap { byDay[$0] ?? [] }
                if !week.isEmpty {
                    weekly.append(notification(prefix: weeklyPrefix, day: date, fire: fire, calendar: calendar, locale: locale,
                                               title: "notification.weekly.title", countKey: "notification.weekly.count %lld",
                                               items: week))
                }
            }
        }

        // Priority: dailies by date, then weeklies by date. Over the cap, weeklies go first, then the latest dailies.
        var result = daily + weekly
        while result.count > maxPending {
            if let lastWeekly = result.lastIndex(where: { $0.identifier.hasPrefix(weeklyPrefix) }) {
                result.remove(at: lastWeekly)
            } else {
                result.removeLast()
            }
        }
        assert(result.count <= maxPending)
        return result
    }

    private static func notification(prefix: String, day: Date, fire: Date, calendar: Calendar, locale: Locale,
                                     title: String, countKey: String, items: [ExpirySnapshot]) -> PlannedNotification {
        let count = CoreLocalization.format(countKey, locale: locale, items.count)
        let body = CoreLocalization.format("notification.body %@ %@", locale: locale, count, names(items, locale: locale))
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return PlannedNotification(
            identifier: prefix + dayString(components),
            fireDate: fire,
            dateComponents: DateComponents(year: components.year, month: components.month, day: components.day,
                                           hour: fireHour, minute: 0),
            title: CoreLocalization.string(title, locale: locale),
            body: body)
    }

    static func names(_ items: [ExpirySnapshot], locale: Locale) -> String {
        let showSpaces = Set(items.map(\.spaceName)).count > 1
        let sorted = items.sorted {
            if $0.expiresAt != $1.expiresAt { return $0.expiresAt < $1.expiresAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let shown = sorted.prefix(namesShown).map { showSpaces ? "\($0.name) (\($0.spaceName))" : $0.name }
        let joined = shown.joined(separator: ", ")
        let remaining = sorted.count - shown.count
        return remaining > 0 ? CoreLocalization.format("notification.names.more %@ %lld", locale: locale, joined, remaining) : joined
    }

    static func dayString(_ components: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
