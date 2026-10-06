import Foundation
import Testing
@testable import LarariCore

@Suite("BackgroundRefreshPolicy")
struct BackgroundRefreshPolicyTests {
    static let budapest: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Self.budapest.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func next(after date: Date) -> Date {
        BackgroundRefreshPolicy.earliestBeginDate(after: date, calendar: Self.budapest)
    }

    @Test func identifierMatchesInfoPlist() {
        #expect(BackgroundRefreshPolicy.taskIdentifier == "app.larari.refresh")
    }

    @Test func beforeHalfPastSixItIsTodaysHalfPastSix() {
        #expect(next(after: at(2026, 10, 5, 5, 0)) == at(2026, 10, 5, 6, 30))
    }

    @Test func eveningGoesToTomorrowsHalfPastSix() {
        #expect(next(after: at(2026, 10, 5, 20, 0)) == at(2026, 10, 6, 6, 30))
    }

    @Test func neverMoreThanTwelveHoursAhead() {
        // 07:00 → the next 06:30 is 23.5 h away, so the 12 h cap wins.
        #expect(next(after: at(2026, 10, 5, 7, 0)) == at(2026, 10, 5, 19, 0))
    }

    @Test func neverSoonerThanFifteenMinutes() {
        #expect(next(after: at(2026, 10, 5, 6, 20)) == at(2026, 10, 5, 6, 35))
        #expect(next(after: at(2026, 10, 5, 6, 30)) == at(2026, 10, 5, 18, 30))   // exactly 06:30: tomorrow's is > 12 h
    }

    @Test func springForwardKeepsLocalHalfPastSix() {
        // 2027-03-28: clocks jump from 02:00 to 03:00 in Budapest.
        let result = next(after: at(2027, 3, 27, 20, 0))
        #expect(result == at(2027, 3, 28, 6, 30))
        #expect(result.timeIntervalSince(at(2027, 3, 27, 20, 0)) == 9.5 * 3600)
    }

    @Test func fallBackCapCountsRealHours() {
        // 2026-10-25: clocks fall back from 03:00 to 02:00. 18:00 → 06:30 is 13.5 real hours, so the cap wins.
        let start = at(2026, 10, 24, 18, 0)
        #expect(next(after: start).timeIntervalSince(start) == 12 * 3600)
        #expect(Self.budapest.component(.hour, from: next(after: start)) == 5)
    }
}
