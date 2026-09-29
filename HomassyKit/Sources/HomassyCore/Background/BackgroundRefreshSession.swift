import Foundation

/// The slice of a `BGTask` a session needs. The app wraps `BGAppRefreshTask` (`SystemBackgroundTask`); tests use a
/// fake. HomassyCore never imports BackgroundTasks, which does not exist on macOS.
public protocol BackgroundTaskHandle: AnyObject, Sendable {
    /// `handler` may be called on any thread.
    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
    func setTaskCompleted(success: Bool)
}

public enum BackgroundRefreshOutcome: Equatable, Sendable {
    case completed, expired
}

/// One background app refresh (N-01). It reschedules first, so a run that is cut short still leaves the next one
/// queued, then runs `steps` in order on the main actor. Expiration cancels the running step and skips the rest.
/// The system task is completed exactly once: success after every step ran, failure on expiration.
@MainActor
public final class BackgroundRefreshSession {
    public private(set) var outcome: BackgroundRefreshOutcome?

    private let task: any BackgroundTaskHandle
    private let steps: [@MainActor () async -> Void]
    private let reschedule: @MainActor () -> Void
    private var work: Task<Void, Never>?

    public init(task: any BackgroundTaskHandle, steps: [@MainActor () async -> Void],
                reschedule: @escaping @MainActor () -> Void) {
        self.task = task
        self.steps = steps
        self.reschedule = reschedule
    }

    public func start() {
        guard work == nil, outcome == nil else { return }
        reschedule()
        // The system calls this on an arbitrary queue, so the closure is `@Sendable` and hops to the main actor
        // explicitly instead of inheriting main-actor isolation (which traps off-main at runtime).
        task.setExpirationHandler { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        let steps = steps
        work = Task { [weak self] in
            for step in steps {
                if Task.isCancelled { break }
                await step()
            }
            self?.finish(Task.isCancelled ? .expired : .completed)
        }
    }

    /// Called by the system's expiration handler (through `start`), or directly.
    public func expire() {
        work?.cancel()
        finish(.expired)
    }

    public func waitUntilFinished() async {
        await work?.value
    }

    private func finish(_ result: BackgroundRefreshOutcome) {
        guard outcome == nil else { return }
        outcome = result
        task.setTaskCompleted(success: result == .completed)
    }
}
