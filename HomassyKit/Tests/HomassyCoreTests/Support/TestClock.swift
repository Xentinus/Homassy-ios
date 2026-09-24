import Foundation
import Synchronization

/// A clock that only moves when a test calls `advance(by:)`.
final class TestClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var cancelledBeforeSleeping: Set<UUID> = []
    }

    private enum Registration { case waiting, due, cancelled }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let registration: Registration = state.withLock { state in
                    if state.cancelledBeforeSleeping.remove(id) != nil { return .cancelled }
                    if deadline <= state.now { return .due }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .waiting
                }
                switch registration {
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .due: continuation.resume()
                case .waiting: break
                }
            }
        } onCancel: {
            let sleeper: Sleeper? = state.withLock { state in
                if let index = state.sleepers.firstIndex(where: { $0.id == id }) {
                    return state.sleepers.remove(at: index)
                }
                state.cancelledBeforeSleeping.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward, wakes every sleeper whose deadline has passed, and lets woken tasks run.
    func advance(by duration: Duration) async {
        await settle()
        let due: [Sleeper] = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
        await settle()
    }

    /// Gives freshly created or freshly woken tasks (including main-actor ones) a chance to run.
    func settle() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
