import Foundation
import Observation

/// The optimistic-change queue behind the undo toast. See P1-08 for the rules ported from the web app. Since N-03
/// every window has its own (`UndoQueueRegistry`).
@MainActor
@Observable
public final class UndoQueue {
    public private(set) var pending: [UndoableAction] = []
    public private(set) var lastError: (any Error)?
    /// Wall-clock start of the current shared window, for the toast's countdown. `nil` when nothing is pending.
    public private(set) var windowStartedAt: Date?

    @ObservationIgnored private let window: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(window: Duration = .seconds(5), clock: any Clock<Duration> = ContinuousClock()) {
        self.window = window
        self.clock = clock
    }

    public var undoWindow: Duration { window }

    /// The newest action's title, or a collapsed count when several are pending.
    public var toastTitle: String? {
        guard let newest = pending.last else { return nil }
        guard pending.count > 1 else { return newest.title }
        let count = pending.reduce(0) { $0 + max(1, $1.entityIDs.count) }
        return UndoTitle.collapsed(kind: dominantKind, count: count)
    }

    /// The kind every pending action shares, or `nil` when they differ or nothing is pending. Drives the toast icon.
    public var dominantKind: UndoKind? {
        let kinds = Set(pending.map(\.kind))
        return kinds.count == 1 ? kinds.first : nil
    }

    /// Adds an action whose change the caller has already applied, and restarts the shared deadline.
    public func enqueue(_ action: UndoableAction) {
        var kept: [UndoableAction] = []
        var toSettle: [UndoableAction] = []
        for existing in pending {
            if existing.entityIDs.isDisjoint(with: action.entityIDs) {
                kept.append(existing)
            } else if existing.entityIDs != action.entityIDs {
                toSettle.append(existing)
            }
            // An exact match is dropped: the newer change already sits on top of it.
        }
        pending = kept + [action]
        for settled in toSettle { runCommit(of: settled) }
        restartTimer()
    }

    public func undo(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let action = pending.remove(at: index)
        action.revert()
        if pending.isEmpty { cancelTimer() }
    }

    public func undoAll() {
        cancelTimer()
        let all = pending
        pending = []
        for action in all.reversed() { action.revert() }
    }

    /// Commits everything now. Every action is attempted; the first failure is rethrown.
    public func commitAll() throws {
        cancelTimer()
        let all = pending
        pending = []
        var firstError: (any Error)?
        for action in all {
            if let error = runCommit(of: action), firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    public func isPending(_ entityID: UUID) -> Bool {
        pending.contains { $0.entityIDs.contains(entityID) }
    }

    public func clearError() {
        lastError = nil
    }

    // MARK: Private

    @discardableResult
    private func runCommit(of action: UndoableAction) -> (any Error)? {
        do {
            try action.commit()
            return nil
        } catch {
            action.revert()
            lastError = error
            return error
        }
    }

    private func expire() {
        timer = nil
        windowStartedAt = nil
        let due = pending
        pending = []
        for action in due { runCommit(of: action) }
    }

    private func restartTimer() {
        timer?.cancel()
        windowStartedAt = .now
        timer = clock.undoTimer(window: window) { [weak self] in self?.expire() }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        windowStartedAt = nil
    }
}

private extension Clock where Duration == Swift.Duration {
    /// Sleeps until `window` after *now* and then fires. The deadline is fixed when this is called
    /// (at enqueue time), not when the task first runs, so a busy main actor cannot stretch the window.
    func undoTimer(window: Duration, fire: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let deadline = now.advanced(by: window)
        return Task { @MainActor in
            do {
                try await sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            fire()
        }
    }
}
