import Foundation

/// Hands every window its own `UndoQueue` (N-03: undo is per window, as in Apple's apps) and remembers them weakly,
/// so the app can save every window's pending changes at once: when it goes to the background, and before an
/// archive import replaces data.
@MainActor
public final class UndoQueueRegistry {
    private final class Entry {
        weak var queue: UndoQueue?
        init(_ queue: UndoQueue) { self.queue = queue }
    }

    private var entries: [Entry] = []
    private let window: Duration
    private let clock: any Clock<Duration>

    public init(window: Duration = .seconds(5), clock: any Clock<Duration> = ContinuousClock()) {
        self.window = window
        self.clock = clock
    }

    /// A new window's queue. The registry does not keep it alive; the window does.
    public func makeQueue() -> UndoQueue {
        let queue = UndoQueue(window: window, clock: clock)
        entries.removeAll { $0.queue == nil }
        entries.append(Entry(queue))
        return queue
    }

    /// The queues of the windows that still exist, oldest first.
    public var queues: [UndoQueue] { entries.compactMap(\.queue) }

    /// Commits every window's pending changes. Every queue is attempted; the first failure is rethrown.
    public func commitAll() throws {
        var firstError: (any Error)?
        for queue in queues {
            do {
                try queue.commitAll()
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
}
