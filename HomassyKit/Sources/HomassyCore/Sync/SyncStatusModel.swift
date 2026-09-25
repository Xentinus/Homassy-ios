import Foundation
import Observation

@MainActor
@Observable
public final class SyncStatusModel {
    public private(set) var lastSuccessfulSync: Date?
    public private(set) var currentError: SyncProblem?
    public private(set) var isPersistent = false
    public private(set) var isSyncing = false

    @ObservationIgnored public var onNotAuthenticated: (@MainActor () -> Void)?

    private struct Entry {
        var problem: SyncProblem
        var firstSeen: Date
        var count: Int
    }

    @ObservationIgnored private let privateStoreIdentifier: String
    @ObservationIgnored private let threshold: Duration
    @ObservationIgnored private let thresholdSeconds: TimeInterval
    @ObservationIgnored private let repeatThreshold: Int
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var entries: [String: Entry] = [:]      // key: "<store>|<kind>"
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var recheckTask: Task<Void, Never>?

    public init(privateStoreIdentifier: String, persistenceThreshold: Duration = .seconds(60),
                repeatThreshold: Int = 3, now: @escaping @MainActor () -> Date = { .now }) {
        self.privateStoreIdentifier = privateStoreIdentifier
        self.threshold = persistenceThreshold
        let parts = persistenceThreshold.components
        self.thresholdSeconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        self.repeatThreshold = repeatThreshold
        self.now = now
    }

    public var bannerProblem: SyncProblem? { isPersistent ? currentError : nil }

    public func handle(_ event: SyncEventSnapshot) {
        guard let endDate = event.endDate else {
            inFlight.insert(event.id)
            isSyncing = true
            return
        }
        inFlight.remove(event.id)
        isSyncing = !inFlight.isEmpty

        let key = "\(event.storeIdentifier)|\(event.kind)"
        if event.succeeded {
            if event.kind != .setup { lastSuccessfulSync = max(lastSuccessfulSync ?? endDate, endDate) }
            entries[key] = nil
        } else {
            let problem = event.failure.map {
                SyncProblem.classify($0, isPrivateStore: event.storeIdentifier == privateStoreIdentifier)
            } ?? .other(code: 0)
            if var entry = entries[key], entry.problem == problem {
                entry.count += 1
                entries[key] = entry
            } else {
                entries[key] = Entry(problem: problem, firstSeen: now(), count: 1)
            }
            if problem == .notAuthenticated { onNotAuthenticated?() }
            scheduleRecheck()
        }
        refresh()
    }

    public func consume(_ events: AsyncStream<SyncEventSnapshot>) async {
        for await event in events { handle(event) }
    }

    /// Recomputes the current problem and whether it is persistent.
    public func refresh() {
        let reference = now()
        let top = entries.values.max { lhs, rhs in
            lhs.problem.priority != rhs.problem.priority
                ? lhs.problem.priority < rhs.problem.priority
                : lhs.firstSeen > rhs.firstSeen
        }
        currentError = top?.problem
        if let top {
            isPersistent = !top.problem.healsOnItsOwn
                || top.count >= repeatThreshold
                || reference.timeIntervalSince(top.firstSeen) >= thresholdSeconds
        } else {
            isPersistent = false
        }
    }

    /// The user exported and/or removed the local copy of a household that is gone.
    public func resolveZoneGone() {
        entries = entries.filter { if case .zoneGone = $0.value.problem { false } else { true } }
        refresh()
    }

    private func scheduleRecheck() {
        recheckTask?.cancel()
        let threshold = threshold
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: threshold)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
