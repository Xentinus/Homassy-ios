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
}
