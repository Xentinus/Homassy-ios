import Foundation
import Testing
@testable import LarariCore

/// N-03: every iPad window has its own undo queue and toast (Apple: undo is per window), and the app can still
/// save all of them at once (background, before an import).
@MainActor
@Suite("UndoQueueRegistry")
struct UndoQueueRegistryTests {
    let clock = TestClock()
    let log = EventLog()

    private func action(_ name: String, failing: Bool = false) -> UndoableAction {
        UndoableAction(title: "\(name) removed", kind: .delete, entityIDs: [UUID()],
                       revert: { [log] in log.events.append("revert \(name)") },
                       commit: { [log] in
                           if failing { throw CommitFailure() }
                           log.events.append("commit \(name)")
                       })
    }

    @Test func eachWindowHasItsOwnQueue() {
        let registry = UndoQueueRegistry(clock: clock)
        let left = registry.makeQueue()
        let right = registry.makeQueue()

        left.enqueue(action("Milk"))
        #expect(left.toastTitle == "Milk removed")
        #expect(right.pending.isEmpty)
        #expect(right.toastTitle == nil)

        right.enqueue(action("Bread"))
        left.undoAll()
        #expect(log.events == ["revert Milk"])
        #expect(right.pending.map(\.title) == ["Bread removed"])
    }

    @Test func newQueuesUseTheRegistrysWindow() {
        #expect(UndoQueueRegistry(window: .seconds(8), clock: clock).makeQueue().undoWindow == .seconds(8))
        #expect(UndoQueueRegistry().makeQueue().undoWindow == .seconds(5))
    }

    @Test func commitAllCommitsEveryWindow() throws {
        let registry = UndoQueueRegistry(clock: clock)
        let left = registry.makeQueue()
        let right = registry.makeQueue()
        left.enqueue(action("Milk"))
        right.enqueue(action("Bread"))

        try registry.commitAll()

        #expect(log.events == ["commit Milk", "commit Bread"])
        #expect(left.pending.isEmpty)
        #expect(right.pending.isEmpty)
    }

    @Test func commitAllTriesEveryWindowAndRethrowsTheFirstFailure() {
        let registry = UndoQueueRegistry(clock: clock)
        let left = registry.makeQueue()
        let right = registry.makeQueue()
        left.enqueue(action("Milk", failing: true))
        right.enqueue(action("Bread"))

        #expect(throws: CommitFailure.self) { try registry.commitAll() }
        #expect(log.events == ["revert Milk", "commit Bread"])
        #expect(left.lastError != nil)
    }

    @Test func aClosedWindowsQueueIsForgotten() {
        let registry = UndoQueueRegistry(clock: clock)
        let kept = registry.makeQueue()
        var closed: UndoQueue? = registry.makeQueue()
        #expect(registry.queues.count == 2)
        #expect(closed != nil)

        closed = nil

        #expect(registry.queues.count == 1)
        #expect(registry.queues.first === kept)
    }
}
