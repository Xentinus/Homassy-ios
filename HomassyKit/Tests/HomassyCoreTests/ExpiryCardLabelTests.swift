import Foundation
import Testing
@testable import HomassyCore

@Suite("ExpirationStatus card label")
struct ExpiryCardLabelTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18, minute: 30))!
    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }
    static func label(_ offset: Int, _ localeID: String) -> String? {
        ExpirationStatus.cardLabel(expiresAt: day(offset), now: now, calendar: calendar, locale: Locale(identifier: localeID))
    }

    @Test("Hungarian card texts", arguments: [
        (0, "Ma lejár"), (1, "Holnap lejár"), (9, "Még 9 nap"), (60, "Még 60 nap"), (-1, "Tegnap lejárt"), (-3, "3 napja lejárt"),
    ])
    func hungarian(offset: Int, expected: String) {
        #expect(Self.label(offset, "hu_HU") == expected)
    }

    @Test("English card texts", arguments: [
        (0, "Expires today"), (1, "Expires tomorrow"), (2, "2 days left"), (-1, "Expired yesterday"), (-5, "Expired 5 days ago"),
    ])
    func english(offset: Int, expected: String) {
        #expect(Self.label(offset, "en_US") == expected)
    }

    @Test("German card texts", arguments: [
        (0, "Läuft heute ab"), (1, "Läuft morgen ab"), (9, "Noch 9 Tage"), (-1, "Gestern abgelaufen"), (-2, "Seit 2 Tagen abgelaufen"),
    ])
    func german(offset: Int, expected: String) {
        #expect(Self.label(offset, "de_DE") == expected)
    }

    @Test("Beyond 60 days the text switches to months, then to years")
    func monthsAndYears() {
        let inEightMonths = Self.calendar.date(byAdding: .month, value: 8, to: Self.day(0))!
        let inThreeYears = Self.calendar.date(byAdding: .year, value: 3, to: Self.day(0))!
        let oneMonthPlus = Self.day(61)
        func label(_ date: Date, _ id: String) -> String? {
            ExpirationStatus.cardLabel(expiresAt: date, now: Self.now, calendar: Self.calendar, locale: Locale(identifier: id))
        }
        #expect(label(inEightMonths, "hu_HU") == "Még 8 hónap")
        #expect(label(inEightMonths, "en_US") == "8 months left")
        #expect(label(inEightMonths, "de_DE") == "Noch 8 Monate")
        #expect(label(oneMonthPlus, "en_US") == "2 months left")
        #expect(label(inThreeYears, "hu_HU") == "Még 3 év")
        #expect(label(inThreeYears, "en_US") == "3 years left")
        #expect(label(inThreeYears, "de_DE") == "Noch 3 Jahre")
    }

    @Test func noDateHasNoLabel() {
        #expect(ExpirationStatus.cardLabel(expiresAt: nil, now: Self.now, calendar: Self.calendar, locale: .current) == nil)
    }
}
