import Foundation
import Testing
@testable import LarariCore

@Suite("NotificationPlanner")
struct NotificationPlannerTests {
    static let budapest: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()
    static let en = Locale(identifier: "en_US")

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        budapest.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func item(_ name: String, _ expiresAt: Date, space: String = "Personal", spaceID: UUID? = nil) -> ExpirySnapshot {
        ExpirySnapshot(id: UUID(), name: name, expiresAt: expiresAt, spaceName: space, spaceID: spaceID)
    }

    /// Thursday 2026-09-24, 06:00 — before today's 07:00.
    static let morning = date(2026, 9, 24, 6, 0)

    static func plan(_ items: [ExpirySnapshot], now: Date = morning, locale: Locale = en,
                     horizon: Int = NotificationPlanner.defaultHorizonDays) -> [PlannedNotification] {
        NotificationPlanner.plan(items: items, now: now, calendar: budapest, locale: locale, horizonDays: horizon)
    }

    static let dairy = [
        item("Milk", date(2026, 9, 24, 0)),
        item("Eggs", date(2026, 9, 25, 0)),
        item("Bread", date(2026, 9, 25, 0)),
        item("Cheese", date(2026, 9, 25, 12)),
    ]

    @Test func dailyCopyAndIdentifiers() {
        let plan = Self.plan(Self.dairy)
        #expect(plan.map(\.identifier) == ["daily-2026-09-24", "daily-2026-09-25"])
        #expect(plan[0].title == "Expiring soon")
        #expect(plan[0].body == "4 items expire today and tomorrow")
        #expect(plan[1].body == "3 items expire today")
        #expect(plan[0].fireDate == Self.date(2026, 9, 24, 7, 0))
        #expect(plan[0].dateComponents == DateComponents(year: 2026, month: 9, day: 24, hour: 7, minute: 0))
    }

    @Test func singularAndTomorrowOnly() {
        let plan = Self.plan([Self.item("Yogurt", Self.date(2026, 9, 26, 9))])
        #expect(plan.map(\.identifier) == ["daily-2026-09-25", "daily-2026-09-26"])
        #expect(plan[0].body == "1 item expires tomorrow")
        #expect(plan[1].body == "1 item expires today")
    }

    @Test("A fire time that has passed is skipped")
    func skipsPastFireTimes() {
        let plan = Self.plan(Self.dairy, now: Self.date(2026, 9, 24, 8, 0))
        #expect(plan.map(\.identifier) == ["daily-2026-09-25"])
    }

    @Test func nothingToSayMeansNoNotifications() {
        #expect(Self.plan([]).isEmpty)
        #expect(Self.plan([Self.item("Rice", Self.date(2026, 12, 1))]).isEmpty)
        #expect(Self.plan([Self.item("Old", Self.date(2026, 9, 1))]).isEmpty)
    }

    @Test("Weekly summaries fire on Mondays and cover Monday to Sunday")
    func weekly() {
        let items = [Self.item("Yogurt", Self.date(2026, 9, 29)), Self.item("Ham", Self.date(2026, 10, 1)),
                     Self.item("Jam", Self.date(2026, 10, 10))]
        let weekly = Self.plan(items).filter { $0.identifier.hasPrefix(NotificationPlanner.weeklyPrefix) }
        #expect(weekly.map(\.identifier) == ["weekly-2026-09-28", "weekly-2026-10-05"])
        #expect(weekly[0].title == "This week")
        #expect(weekly[0].body == "2 items expire this week")
        #expect(weekly[1].body == "1 item expires this week")
        #expect(weekly[0].fireDate == Self.date(2026, 9, 28, 7, 0))
        let dailies = Self.plan(items).filter { $0.identifier.hasPrefix(NotificationPlanner.dailyPrefix) }
        #expect(dailies.map(\.identifier) == ["daily-2026-09-28", "daily-2026-09-29", "daily-2026-09-30", "daily-2026-10-01"])
    }

    /// The body only says what is wrong; a tap shows the items (user request, 2026-09-26). The tap opens the space
    /// with most of the items.
    @Test func bodyHasNoNamesAndTheTargetIsTheSpaceWithMostItems() {
        let home = UUID(), personal = UUID()
        let plan = Self.plan([Self.item("Milk", Self.date(2026, 9, 25), spaceID: personal),
                              Self.item("Bread", Self.date(2026, 9, 25), spaceID: home),
                              Self.item("Eggs", Self.date(2026, 9, 25), spaceID: home)])
        #expect(plan[0].body == "3 items expire tomorrow")
        #expect(plan[0].targetSpaceID == home)
    }

    @Test("500 items never produce more than 64 notifications")
    func fiveHundredItems() {
        let items = (0..<500).map { Self.item("Item \($0)", Self.budapest.date(byAdding: .day, value: $0 % 30, to: Self.morning)!) }
        let plan = Self.plan(items)
        #expect(plan.count <= NotificationPlanner.maxPending)
        #expect(plan.count == 16)                                 // 14 dailies + 2 Mondays
        #expect(plan.allSatisfy { !$0.body.contains(":") })          // counts only, never item names
        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }

    @Test("Over the cap, weeklies go first, then the latest dailies")
    func trimming() {
        let items = (0..<70).map { Self.item("Item \($0)", Self.budapest.date(byAdding: .day, value: $0, to: Self.morning)!) }
        let sixty = Self.plan(items, horizon: 60)
        #expect(sixty.count == 64)
        #expect(sixty.filter { $0.identifier.hasPrefix("daily-") }.count == 60)
        #expect(sixty.filter { $0.identifier.hasPrefix("weekly-") }.map(\.identifier)
                == ["weekly-2026-09-28", "weekly-2026-10-05", "weekly-2026-10-12", "weekly-2026-10-19"])

        let hundred = Self.plan(items + (70..<120).map { Self.item("Late \($0)", Self.budapest.date(byAdding: .day, value: $0, to: Self.morning)!) },
                                horizon: 100)
        #expect(hundred.count == 64)
        #expect(hundred.allSatisfy { $0.identifier.hasPrefix("daily-") })
        #expect(hundred.last?.identifier == "daily-2026-11-26")
    }

    @Test("DST keeps 07:00 local")
    func daylightSaving() {
        let plan = Self.plan([Self.item("Milk", Self.date(2026, 3, 29, 12)), Self.item("Bread", Self.date(2026, 3, 30, 12))],
                             now: Self.date(2026, 3, 27, 20, 0))
        let dailies = plan.filter { $0.identifier.hasPrefix("daily-") }
        #expect(dailies.map(\.identifier) == ["daily-2026-03-28", "daily-2026-03-29", "daily-2026-03-30"])
        for notification in dailies {
            #expect(Self.budapest.component(.hour, from: notification.fireDate) == 7)
            #expect(notification.dateComponents.hour == 7 && notification.dateComponents.minute == 0)
        }
        #expect(dailies[1].fireDate.timeIntervalSince(dailies[0].fireDate) == 23 * 3600)
        #expect(dailies[2].fireDate.timeIntervalSince(dailies[1].fireDate) == 24 * 3600)
    }

    @Test func identifiersAreStableWithinADay() {
        let early = Self.plan(Self.dairy, now: Self.date(2026, 9, 24, 5, 0))
        let later = Self.plan(Self.dairy, now: Self.date(2026, 9, 24, 6, 45))
        #expect(early == later)
    }

    @Test func hungarianAndGermanCopy() {
        let hu = Self.plan([Self.item("Tej", Self.date(2026, 9, 24, 18))], locale: Locale(identifier: "hu_HU"))
        #expect(hu[0].title == "Hamarosan lejár")
        #expect(hu[0].body == "1 tétel ma lejár")
        let de = Self.plan([Self.item("Brot", Self.date(2026, 9, 25)), Self.item("Käse", Self.date(2026, 9, 25))],
                           locale: Locale(identifier: "de_DE"))
        #expect(de[0].title == "Läuft bald ab")
        #expect(de[0].body == "2 Artikel laufen morgen ab")
        let many = (0..<5).map { Self.item("Termék \($0)", Self.date(2026, 9, 24, 12)) }
        #expect(Self.plan(many, locale: Locale(identifier: "hu_HU"))[0].body == "5 tétel ma lejár")
    }

    @Test func everyKeyIsTranslated() {
        let keys = ["notification.daily.title", "notification.weekly.title", "notification.daily.today %lld",
                    "notification.daily.tomorrow %lld", "notification.daily.todayAndTomorrow %lld",
                    "notification.weekly.count %lld"]
        for key in keys {
            for id in ["hu_HU", "en_US", "de_DE"] {
                #expect(CoreLocalization.lookup(key, locale: Locale(identifier: id)) != nil, "\(key) \(id)")
            }
        }
    }
}
