import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Store reminder scheduling")
struct StoreReminderSchedulerTests {
    func reminder(_ index: Int) -> PlannedStoreReminder {
        PlannedStoreReminder(identifier: "store-auchan-\(index)", title: "t", body: "b",
                             center: Coordinate(latitude: 47, longitude: 19), radius: 150)
    }

    func daily(_ index: Int) -> PlannedNotification {
        PlannedNotification(identifier: "daily-2026-10-\(String(format: "%02d", index + 1))", fireDate: .now,
                            dateComponents: DateComponents(), title: "t", body: "b")
    }

    @Test func replacesOnlyStoreRequests() async {
        let center = FakeNotificationCenter(foreign: ["other"])
        await center.seedOwn(["daily-2026-10-01"])
        await center.seedLocation(["store-old-0"])
        let scheduler = NotificationScheduler(center: center)

        let added = await scheduler.rescheduleStoreReminders([reminder(0), reminder(1)])

        #expect(added.count == 2)
        #expect(await center.identifiers == ["daily-2026-10-01", "other", "store-auchan-0", "store-auchan-1"])
    }

    @Test func storeBudgetIsCappedAtTwentyAndBySixtyFour() async {
        let scheduler = NotificationScheduler(center: FakeNotificationCenter(foreign: (0..<50).map { "f\($0)" }))
        let added = await scheduler.rescheduleStoreReminders((0..<30).map(reminder))
        #expect(added.count == 14)                                // 64 - 50

        let roomy = NotificationScheduler(center: FakeNotificationCenter())
        #expect(await roomy.rescheduleStoreReminders((0..<30).map(reminder)).count == 20)
    }

    @Test func expirySummariesKeepPriorityOverStoreReminders() async {
        let center = FakeNotificationCenter(foreign: (0..<40).map { "f\($0)" })
        await center.seedLocation((0..<20).map { "store-auchan-\($0)" })
        let scheduler = NotificationScheduler(center: center)

        let added = await scheduler.reschedule((0..<16).map(daily))

        #expect(added.count == 16)                                // store requests do not count against the summaries
        let ids = await center.identifiers
        #expect(ids.count == 64)                                  // 4 store requests were evicted
        #expect(ids.filter { $0.hasPrefix("store-") }.count == 8)
        #expect(ids.contains("store-auchan-0") && !ids.contains("store-auchan-19"))   // the lowest ranks stay
    }

    @Test func emptyPlanRemovesEveryStoreRequest() async {
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-a-0", "store-b-0"])
        #expect(await NotificationScheduler(center: center).rescheduleStoreReminders([]).isEmpty)
        #expect(await center.identifiers.isEmpty)
    }
}
