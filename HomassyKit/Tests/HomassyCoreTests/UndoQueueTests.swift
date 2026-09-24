import Foundation
import Testing
@testable import HomassyCore

struct CommitFailure: Error {}

@MainActor
final class EventLog {
    var events: [String] = []
}

@MainActor
@Suite("UndoQueue")
struct UndoQueueTests {
    let clock = TestClock()
    let log = EventLog()

    private func makeQueue() -> UndoQueue { UndoQueue(window: .seconds(5), clock: clock) }

    private func action(_ name: String, kind: UndoKind = .delete, entities: [UUID] = [],
                        failing: Bool = false) -> UndoableAction {
        UndoableAction(title: "\(name) removed", kind: kind, entityIDs: entities,
                       revert: { [log] in log.events.append("revert \(name)") },
                       commit: { [log] in
                           if failing { throw CommitFailure() }
                           log.events.append("commit \(name)")
                       })
    }

    @Test func defaultWindowIsFiveSeconds() {
        #expect(UndoQueue().undoWindow == .seconds(5))
    }

    @Test func initDefaultsToGenericKindAndNoEntities() {
        let action = UndoableAction(title: "Renamed", revert: {}, commit: {})
        #expect(action.kind == .generic)
        #expect(action.entityIDs.isEmpty)

        let id = UUID()
        #expect(UndoableAction(title: "Twice", entityIDs: [id, id], revert: {}, commit: {}).entityIDs == [id])
    }

    @Test func genericActionsCollapseToTheMixedCount() {
        let queue = makeQueue()
        queue.enqueue(action("A", kind: .generic))
        queue.enqueue(action("B", kind: .generic))
        #expect(queue.toastTitle == UndoTitle.collapsed(kind: nil, count: 2))
        #expect(UndoTitle.collapsed(kind: .generic, count: 2) == UndoTitle.collapsed(kind: nil, count: 2))
    }

    @Test func commitsWhenTheWindowEnds() async throws {
        let queue = makeQueue()
        queue.enqueue(action("A"))
        await clock.advance(by: .milliseconds(4900))
        #expect(log.events.isEmpty)
        #expect(queue.pending.count == 1)

        await clock.advance(by: .milliseconds(100))
        try await waitUntil { log.events == ["commit A"] }
        #expect(log.events == ["commit A"])
        #expect(queue.pending.isEmpty)
    }

    @Test func undoRevertsAndNeverCommits() async {
        let queue = makeQueue()
        let a = action("A")
        queue.enqueue(a)
        queue.undo(a.id)

        #expect(log.events == ["revert A"])
        #expect(queue.pending.isEmpty)
        await clock.advance(by: .seconds(10))
        #expect(log.events == ["revert A"])
    }

    @Test func enqueueResetsTheSharedDeadline() async throws {
        let queue = makeQueue()
        queue.enqueue(action("A"))
        await clock.advance(by: .seconds(3))
        queue.enqueue(action("B"))
        await clock.advance(by: .seconds(3))
        #expect(log.events.isEmpty)

        await clock.advance(by: .seconds(2))
        try await waitUntil { log.events == ["commit A", "commit B"] }
        #expect(log.events == ["commit A", "commit B"])
    }

    @Test func exactEntityMatchReplacesTheOlderAction() async throws {
        let queue = makeQueue()
        let item = UUID()
        let older = action("A", entities: [item])
        queue.enqueue(older)
        queue.enqueue(action("B", entities: [item]))

        #expect(queue.pending.map(\.title) == ["B removed"])
        #expect(log.events.isEmpty)
        await clock.advance(by: .seconds(5))
        try await waitUntil { log.events == ["commit B"] }
        #expect(log.events == ["commit B"])
    }

    @Test func partialOverlapSettlesTheOlderActionNow() {
        let queue = makeQueue()
        let (one, two, three) = (UUID(), UUID(), UUID())
        queue.enqueue(action("A", kind: .move, entities: [one, two]))
        queue.enqueue(action("B", entities: [two, three]))

        #expect(log.events == ["commit A"])
        #expect(queue.pending.map(\.title) == ["B removed"])
    }

    @Test func disjointActionsBothStayPending() {
        let queue = makeQueue()
        queue.enqueue(action("A", entities: [UUID()]))
        queue.enqueue(action("B", entities: [UUID()]))
        #expect(queue.pending.count == 2)
    }

    @Test func failedCommitRevertsAndKeepsTheError() async throws {
        let queue = makeQueue()
        queue.enqueue(action("A", failing: true))
        await clock.advance(by: .seconds(5))
        try await waitUntil { log.events == ["revert A"] }

        #expect(log.events == ["revert A"])
        #expect(queue.lastError is CommitFailure)
        queue.clearError()
        #expect(queue.lastError == nil)
    }

    @Test func commitAllCommitsEverythingOnce() async throws {
        let queue = makeQueue()
        queue.enqueue(action("A"))
        queue.enqueue(action("B"))
        try queue.commitAll()

        #expect(log.events == ["commit A", "commit B"])
        #expect(queue.pending.isEmpty)
        await clock.advance(by: .seconds(10))
        #expect(log.events == ["commit A", "commit B"])
    }

    @Test func commitAllRethrowsTheFirstFailureAfterTryingEveryAction() {
        let queue = makeQueue()
        queue.enqueue(action("A", failing: true))
        queue.enqueue(action("B"))

        #expect(throws: CommitFailure.self) { try queue.commitAll() }
        #expect(log.events == ["revert A", "commit B"])
        #expect(queue.lastError is CommitFailure)
    }

    @Test func undoAllRevertsNewestFirst() async {
        let queue = makeQueue()
        queue.enqueue(action("A"))
        queue.enqueue(action("B"))
        queue.undoAll()

        #expect(log.events == ["revert B", "revert A"])
        await clock.advance(by: .seconds(10))
        #expect(log.events == ["revert B", "revert A"])
    }

    @Test func isPendingChecksEntityIDs() {
        let queue = makeQueue()
        let item = UUID()
        queue.enqueue(action("A", entities: [item]))
        #expect(queue.isPending(item))
        #expect(!queue.isPending(UUID()))
    }

    @Test func toastTitleIsTheOnlyActionsTitle() {
        let queue = makeQueue()
        #expect(queue.toastTitle == nil)
        queue.enqueue(action("A"))
        #expect(queue.toastTitle == "A removed")
    }

    @Test func toastTitleCollapsesByEntityCount() {
        let queue = makeQueue()
        queue.enqueue(action("A", entities: [UUID(), UUID()]))
        queue.enqueue(action("B"))
        #expect(queue.toastTitle == UndoTitle.collapsed(kind: .delete, count: 3))
        #expect(queue.toastTitle?.contains("3") == true)

        queue.enqueue(action("C", kind: .purchase))
        #expect(queue.toastTitle == UndoTitle.collapsed(kind: nil, count: 4))
    }

    @Test func windowStartTracksTheSharedDeadline() async throws {
        let queue = makeQueue()
        #expect(queue.windowStartedAt == nil)
        queue.enqueue(action("A"))
        let first = try #require(queue.windowStartedAt)
        try await Task.sleep(for: .milliseconds(5))
        queue.enqueue(action("B"))
        let second = try #require(queue.windowStartedAt)
        #expect(second > first)                       // a new enqueue restarts the shared window
        queue.undoAll()
        #expect(queue.windowStartedAt == nil)
    }

    @Test func windowStartClearsWhenTheWindowCommits() async throws {
        let queue = makeQueue()
        queue.enqueue(action("A"))
        await clock.advance(by: .seconds(5))
        try await waitUntil { queue.pending.isEmpty }
        #expect(queue.windowStartedAt == nil)
    }

    @Test func dominantKindIsTheSharedKindOrNil() {
        let queue = makeQueue()
        #expect(queue.dominantKind == nil)
        queue.enqueue(action("A", kind: .move))
        queue.enqueue(action("B", kind: .move))
        #expect(queue.dominantKind == .move)
        queue.enqueue(action("C", kind: .consume))
        #expect(queue.dominantKind == nil)
    }

    @Test func itemTitlesContainTheName() {
        for title in [UndoTitle.removed("Milk"), UndoTitle.purchased("Milk"), UndoTitle.moved("Milk"), UndoTitle.consumed("Milk")] {
            #expect(title.contains("Milk"))
            #expect(!title.contains("%@"))
        }
        for kind in UndoKind.allCases {
            #expect(UndoTitle.collapsed(kind: kind, count: 7).contains("7"))
        }
    }
}
