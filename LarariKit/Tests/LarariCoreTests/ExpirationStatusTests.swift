import Foundation
import Testing
@testable import LarariCore

@Suite("ExpirationStatus")
struct ExpirationStatusTests {
    static let budapest: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        calendar.locale = Locale(identifier: "hu_HU")
        return calendar
    }()
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                     in calendar: Calendar = budapest) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2026-09-24 18:30 in Budapest.
    static let now = date(2026, 9, 24, 18, 30)

    static func expiry(inDays days: Int, hour: Int = 0) -> Date {
        let day = budapest.date(byAdding: .day, value: days, to: budapest.startOfDay(for: now))!
        return budapest.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    /// The inventory.section.soon strings ("Within 14 days" / "14 napon belül" / "In den nächsten 14 Tagen") write the
    /// number out, so a change here must change them (P2-08e).
    @Test func soonDaysIsTheFourteenTheSectionTitleSays() {
        #expect(ExpirationStatus.soonDays == 14)
    }

    @Test("Boundary days", arguments: [
        (-30, ExpirationLevel.expired), (-1, .expired), (0, .critical), (1, .critical), (3, .critical),
        (4, .soon), (13, .soon), (14, .soon), (15, .ok), (400, .ok),
    ])
    func boundaries(days: Int, expected: ExpirationLevel) {
        for hour in [0, 12, 23] {
            let expiresAt = Self.expiry(inDays: days, hour: hour)
            #expect(ExpirationStatus.daysUntilExpiration(expiresAt, now: Self.now, calendar: Self.budapest) == days)
            #expect(ExpirationStatus.level(expiresAt: expiresAt, now: Self.now, calendar: Self.budapest) == expected)
        }
    }

    @Test func noDateIsNone() {
        #expect(ExpirationStatus.daysUntilExpiration(nil, now: Self.now, calendar: Self.budapest) == nil)
        #expect(ExpirationStatus.level(expiresAt: nil, now: Self.now, calendar: Self.budapest) == .none)
    }

    @Test("Earlier today is still day 0, so critical and not expired")
    func earlierToday() {
        let morning = Self.date(2026, 9, 24, 6, 0)
        #expect(ExpirationStatus.level(expiresAt: morning, now: Self.now, calendar: Self.budapest) == .critical)
    }

    @Test("Spring DST change counts calendar days")
    func springForward() {
        let now = Self.date(2026, 3, 28, 12, 0)          // CET, the day before clocks move forward
        #expect(ExpirationStatus.daysUntilExpiration(Self.date(2026, 3, 29, 23, 0), now: now, calendar: Self.budapest) == 1)
        #expect(ExpirationStatus.level(expiresAt: Self.date(2026, 3, 31, 0, 30), now: now, calendar: Self.budapest) == .critical)
        #expect(ExpirationStatus.level(expiresAt: Self.date(2026, 4, 1), now: now, calendar: Self.budapest) == .soon)
        #expect(ExpirationStatus.level(expiresAt: Self.date(2026, 4, 11), now: now, calendar: Self.budapest) == .soon)
        #expect(ExpirationStatus.level(expiresAt: Self.date(2026, 4, 12), now: now, calendar: Self.budapest) == .ok)
    }

    @Test("Autumn DST change (25-hour day) counts calendar days")
    func fallBack() {
        let now = Self.date(2026, 10, 24, 23, 30)
        #expect(ExpirationStatus.daysUntilExpiration(Self.date(2026, 10, 25, 23, 30), now: now, calendar: Self.budapest) == 1)
        #expect(ExpirationStatus.daysUntilExpiration(Self.date(2026, 10, 26, 0, 0), now: now, calendar: Self.budapest) == 2)
    }

    @Test("The calendar's time zone decides which day an instant falls on")
    func timeZone() {
        let now = Self.date(2026, 10, 1, 10, 0, in: Self.utc)         // 12:00 in Budapest
        let expiresAt = Self.date(2026, 10, 1, 23, 30, in: Self.utc)  // 01:30 on Oct 2 in Budapest
        #expect(ExpirationStatus.daysUntilExpiration(expiresAt, now: now, calendar: Self.budapest) == 1)
        #expect(ExpirationStatus.daysUntilExpiration(expiresAt, now: now, calendar: Self.utc) == 0)
    }

    @Test func attention() {
        #expect(!ExpirationLevel.none.isAttention)
        #expect(!ExpirationLevel.ok.isAttention)
        #expect(ExpirationLevel.soon.isAttention)
        #expect(ExpirationLevel.critical.isAttention)
        #expect(ExpirationLevel.expired.isAttention)
        #expect(ExpirationLevel.none < .ok && ExpirationLevel.ok < .soon && ExpirationLevel.soon < .critical && ExpirationLevel.critical < .expired)
    }

    @Test func worst() {
        let dates: [Date?] = [nil, Self.expiry(inDays: 20), Self.expiry(inDays: 2), Self.expiry(inDays: 10)]
        #expect(ExpirationStatus.worstLevel(dates, now: Self.now, calendar: Self.budapest) == .critical)
        #expect(ExpirationStatus.worstLevel([], now: Self.now, calendar: Self.budapest) == .none)
        #expect(ExpirationStatus.worstLevel([nil], now: Self.now, calendar: Self.budapest) == .none)
    }

    @Test("Sort key: severity first, then date, nil last")
    func sortKey() {
        let input: [(String, Date?)] = [
            ("none", nil), ("ok", Self.expiry(inDays: 30)), ("soon10", Self.expiry(inDays: 10)),
            ("soon5", Self.expiry(inDays: 5)), ("critical", Self.expiry(inDays: 1)),
            ("expiredRecent", Self.expiry(inDays: -1)), ("expiredOld", Self.expiry(inDays: -9)),
        ]
        let sorted = input.shuffled().sorted {
            ExpirationStatus.sortKey(expiresAt: $0.1, now: Self.now, calendar: Self.budapest)
                < ExpirationStatus.sortKey(expiresAt: $1.1, now: Self.now, calendar: Self.budapest)
        }
        #expect(sorted.map(\.0) == ["expiredOld", "expiredRecent", "critical", "soon5", "soon10", "ok", "none"])
    }

    @Test("English chip labels", arguments: [
        (0, "Today"), (1, "Tomorrow"), (3, "In 3 days"), (14, "In 14 days"),
        (-1, "Expired yesterday"), (-2, "Expired 2 days ago"),
    ])
    func englishLabels(days: Int, expected: String) {
        let label = ExpirationStatus.label(expiresAt: Self.expiry(inDays: days), now: Self.now,
                                           calendar: Self.budapest, locale: Locale(identifier: "en_US"))
        #expect(label == expected)
    }

    @Test func labelOutsideWindowIsAbsoluteDate() {
        let locale = Locale(identifier: "en_US")
        let far = Self.date(2026, 12, 25, 0, 0)
        let label = ExpirationStatus.label(expiresAt: far, now: Self.now, calendar: Self.budapest, locale: locale)
        #expect(label == "Dec 25, 2026")
        #expect(ExpirationStatus.label(expiresAt: nil, now: Self.now, calendar: Self.budapest, locale: locale) == nil)
    }

    @Test("Expired prefix is translated", arguments: [("hu_HU", "Lejárt "), ("de_DE", "Abgelaufen "), ("en_US", "Expired ")])
    func expiredPrefix(localeID: String, prefix: String) {
        let label = ExpirationStatus.label(expiresAt: Self.expiry(inDays: -3), now: Self.now,
                                           calendar: Self.budapest, locale: Locale(identifier: localeID))
        #expect(label?.hasPrefix(prefix) == true)
        #expect(CoreLocalization.lookup("expiration.expiredRelative %@", locale: Locale(identifier: localeID)) != nil)
    }
}
