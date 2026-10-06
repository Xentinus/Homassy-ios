import BackgroundTasks
import Foundation
import LarariCore
import os

/// BGTaskScheduler glue for the background app refresh (N-01). What to refresh, in which order and when to ask
/// again lives in LarariCore (`BackgroundRefreshPolicy`, `BackgroundRefreshSession`,
/// `ServiceContainer.backgroundRefreshSteps`); this file registers, submits and wraps the system task.
enum BackgroundRefresh {
    private static let log = Logger(subsystem: "app.larari", category: "background-refresh")
    /// The running session, kept alive until the system task is completed.
    private static var current: BackgroundRefreshSession?

    /// Must run before `application(_:didFinishLaunchingWithOptions:)` returns. `using: .main` delivers the task on
    /// the main thread, so the handler can assume main-actor isolation.
    static func register() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshPolicy.taskIdentifier, using: .main
        ) { task in
            MainActor.assumeIsolated { handle(task) }
        }
        if !registered {
            log.error("Background refresh was not registered; check BGTaskSchedulerPermittedIdentifiers in Info.plist")
        }
    }

    /// Asks iOS for the next run (it replaces a pending request with the same identifier). Called at launch, when
    /// the scene goes to the background, and at the start of every run.
    static func submit(now: Date = .now) {
        #if DEBUG
        if UITestHooks.isActive { return }      // UI tests run against an in-memory store
        #endif
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshPolicy.taskIdentifier)
        request.earliestBeginDate = BackgroundRefreshPolicy.earliestBeginDate(after: now, calendar: .current)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // `.unavailable` when Background App Refresh is off for Larari; nothing to do then.
            log.notice("Background refresh not submitted: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGTask) {
        let session = BackgroundRefreshSession(task: SystemBackgroundTask(task),
                                               steps: [{ await runSteps() }],
                                               reschedule: { submit() })
        current = session
        session.start()
        // The session only holds itself weakly (its expiration handler and work task), so this task owns it
        // until `waitUntilFinished()` returns; otherwise it could deallocate mid-run and the BGTask would never
        // be completed.
        Task { @MainActor in
            await session.waitUntilFinished()
            let outcome = session.outcome.map { "\($0)" } ?? "none"
            log.info("Background refresh finished: \(outcome, privacy: .public)")
            if current === session { current = nil }
        }
    }

    private static func runSteps() async {
        guard let services = await AppModel.shared.prepareServices() else {
            if Task.isCancelled {
                log.notice("Background refresh cancelled while preparing services")
            } else {
                log.notice("Background refresh skipped: no services (account unavailable or bootstrap failed)")
            }
            return
        }
        for step in services.backgroundRefreshSteps {
            if Task.isCancelled { return }
            await step()
        }
        log.info("""
            Background refresh: \(services.notifications.lastPlan.count, privacy: .public) summaries, \
            badge \(services.notifications.lastBadgeCount ?? -1, privacy: .public), \
            \(services.storeReminders.lastPlan.count, privacy: .public) store reminders
            """)
    }
}

/// Wraps the system task for `BackgroundRefreshSession`. `nonisolated`, with an explicitly `@Sendable` handler:
/// BGTask calls the expiration handler on a background queue, and a closure the app target infers as
/// MainActor-isolated would trap there (the same class of crash as the notification-delegate fix 2732862). The
/// session hops to the main actor itself.
nonisolated final class SystemBackgroundTask: BackgroundTaskHandle, @unchecked Sendable {
    private let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = { @Sendable in handler() }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
