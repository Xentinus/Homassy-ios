import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("BackgroundRefreshSession")
struct BackgroundRefreshSessionTests {
    @MainActor final class Log {
        var entries: [String] = []
    }

    @Test func reschedulesFirstThenRunsEveryStepAndCompletesOnce() async {
        let task = FakeBackgroundTask()
        let log = Log()
        let session = BackgroundRefreshSession(
            task: task,
            steps: [{ log.entries.append("expiry") }, { log.entries.append("store") }],
            reschedule: { log.entries.append("reschedule") })

        session.start()
        await session.waitUntilFinished()

        #expect(log.entries == ["reschedule", "expiry", "store"])
        #expect(session.outcome == .completed)
        #expect(task.completions == [true])
    }

    @Test func expirationCancelsTheRunningStepAndSkipsTheRest() async {
        let task = FakeBackgroundTask()
        let log = Log()
        let session = BackgroundRefreshSession(
            task: task,
            steps: [
                {
                    log.entries.append("slow started")
                    do { try await Task.sleep(for: .seconds(30)) } catch { log.entries.append("slow cancelled") }
                },
                { log.entries.append("store") },
            ],
            reschedule: {})

        session.start()
        while !log.entries.contains("slow started") { await Task.yield() }
        await task.fireExpiration()                       // from a background thread, like BGTask
        await session.waitUntilFinished()

        #expect(log.entries == ["slow started", "slow cancelled"])
        #expect(session.outcome == .expired)
        #expect(task.completions == [false])
    }

    @Test func expirationBeforeTheFirstStepRunsNothing() async {
        let task = FakeBackgroundTask()
        let log = Log()
        let session = BackgroundRefreshSession(task: task, steps: [{ log.entries.append("expiry") }],
                                               reschedule: { log.entries.append("reschedule") })
        session.start()
        session.expire()
        await session.waitUntilFinished()

        #expect(log.entries == ["reschedule"])            // the next run is still queued
        #expect(session.outcome == .expired)
        #expect(task.completions == [false])
    }

    @Test func expirationBeforeStartRunsNothingAndCompletesOnce() async {
        let task = FakeBackgroundTask()
        let log = Log()
        let session = BackgroundRefreshSession(task: task, steps: [{ log.entries.append("step") }],
                                               reschedule: { log.entries.append("reschedule") })
        session.expire()
        session.start()
        await session.waitUntilFinished()
        for _ in 0..<10 { await Task.yield() }

        #expect(log.entries.isEmpty)
        #expect(session.outcome == .expired)
        #expect(task.completions == [false])
    }

    @Test func expirationAfterCompletionReportsNothingMore() async {
        let task = FakeBackgroundTask()
        let session = BackgroundRefreshSession(task: task, steps: [{}], reschedule: {})
        session.start()
        await session.waitUntilFinished()
        await task.fireExpiration()
        for _ in 0..<10 { await Task.yield() }

        #expect(session.outcome == .completed)
        #expect(task.completions == [true])
    }

    @Test func startingTwiceRunsOnce() async {
        let task = FakeBackgroundTask()
        let log = Log()
        let session = BackgroundRefreshSession(task: task, steps: [{ log.entries.append("step") }],
                                               reschedule: { log.entries.append("reschedule") })
        session.start()
        session.start()
        await session.waitUntilFinished()

        #expect(log.entries == ["reschedule", "step"])
        #expect(task.completions == [true])
    }

    @Test func containerStepsRecomputeTheSummariesAndTheBadge() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let center = FakeNotificationCenter()
        let services = ServiceContainer(spaceStore: env.spaceStore, context: env.context,
                                        userRecordName: ServiceTestEnvironment.user,
                                        notificationCenter: center, storeSearch: FakeStoreSearch())
        // The container's coordinators use the real clock, so the fixture is relative to today.
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        _ = try services.inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: tomorrow,
                                            purchasedAt: nil, price: nil, currency: nil,
                                            storageLocation: nil, shoppingLocation: nil)
        let task = FakeBackgroundTask()

        let session = BackgroundRefreshSession(task: task, steps: services.backgroundRefreshSteps, reschedule: {})
        session.start()
        await session.waitUntilFinished()

        #expect(await center.badge == 1)
        #expect(await center.identifiers.contains { $0.hasPrefix(NotificationPlanner.dailyPrefix) })
        #expect(services.storeReminders.lastPlan.isEmpty)       // no location authorizer: store reminders stay idle
        #expect(task.completions == [true])
    }
}
