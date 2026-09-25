import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Backup reminder")
struct BackupReminderTests {
    let calendar: Calendar
    let start: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Budapest"))
        self.calendar = calendar
        start = ArchiveTestStack.date("2026-01-01T09:00:00+01:00")
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private func remind(at now: Date, export: Date? = nil, dismiss: Date? = nil, firstUse: Date? = nil) -> Bool {
        BackupReminder.shouldRemind(now: now, firstUseAt: firstUse ?? start, lastExportAt: export,
                                    lastDismissedAt: dismiss, calendar: calendar)
    }

    @Test func silentUntilFirstUseIsKnown() {
        #expect(!BackupReminder.shouldRemind(now: day(400), firstUseAt: nil, lastExportAt: nil,
                                             lastDismissedAt: nil, calendar: calendar))
    }

    @Test func silentDuringTheFirstFourteenDays() {
        #expect(!remind(at: day(13)))
        #expect(remind(at: day(14)))
    }

    @Test func remindsThirtyDaysAfterTheLastExport() {
        #expect(!remind(at: day(49), export: day(20)))
        #expect(remind(at: day(50), export: day(20)))
    }

    @Test func dismissingPostponesByThirtyDays() {
        #expect(!remind(at: day(60), export: day(15), dismiss: day(46)))
        #expect(remind(at: day(76), export: day(15), dismiss: day(46)))
    }

    @Test func theLaterOfExportAndDismissCounts() {
        #expect(!remind(at: day(69), export: day(40), dismiss: day(20)))
        #expect(remind(at: day(70), export: day(40), dismiss: day(20)))
    }

    @Test func graceStillAppliesAfterAnEarlyExport() {
        #expect(!remind(at: day(10), export: day(1)))
    }

    @Test func statePersistsInDefaults() throws {
        let suite = "BackupReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let reminder = BackupReminder(defaults: defaults, calendar: calendar)
        reminder.recordFirstUseIfNeeded(now: start)
        reminder.recordFirstUseIfNeeded(now: day(5))
        #expect(reminder.firstUseAt == start)
        #expect(reminder.shouldRemind(now: day(14)))
        reminder.dismiss(now: day(14))
        #expect(!reminder.shouldRemind(now: day(15)))
        reminder.recordExport(now: day(20))

        let reloaded = BackupReminder(defaults: defaults, calendar: calendar)
        #expect(reloaded.firstUseAt == start)
        #expect(reloaded.lastDismissedAt == day(14))
        #expect(reloaded.lastExportAt == day(20))
        #expect(!reloaded.shouldRemind(now: day(49)))
        #expect(reloaded.shouldRemind(now: day(50)))
    }
}
