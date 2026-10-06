import Foundation
import Observation

public struct Attribution: Equatable, Sendable {
    public let userRecordName: String
    public let until: Date

    public init(userRecordName: String, until: Date) {
        self.userRecordName = userRecordName
        self.until = until
    }
}

/// Rows recently changed by someone else, keyed by publicId (§5 Remote changes).
@MainActor
@Observable
public final class AttributionTracker {
    public static let defaultWindow: Duration = .milliseconds(1500)

    public private(set) var recentlyChangedByOthers: [UUID: Attribution] = [:]

    @ObservationIgnored private let window: TimeInterval
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init(window: Duration = AttributionTracker.defaultWindow, now: @escaping @MainActor () -> Date = { .now }) {
        let parts = window.components
        self.window = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        self.now = now
    }

    public func record(_ changes: [ForeignChange]) {
        guard !changes.isEmpty else { return }
        let until = now().addingTimeInterval(window)
        for change in changes {
            recentlyChangedByOthers[change.publicId] = Attribution(userRecordName: change.userRecordName, until: until)
        }
        scheduleExpiry()
    }

    public func attribution(for publicId: UUID) -> Attribution? {
        guard let attribution = recentlyChangedByOthers[publicId], attribution.until > now() else { return nil }
        return attribution
    }

    /// For a card that shows several records (a product and its stock items): the most recent live change.
    public func attribution(forAnyOf publicIds: Set<UUID>) -> Attribution? {
        publicIds.compactMap(attribution(for:)).max { $0.until < $1.until }
    }

    public func pruneExpired() {
        let reference = now()
        let live = recentlyChangedByOthers.filter { $0.value.until > reference }
        if live.count != recentlyChangedByOthers.count { recentlyChangedByOthers = live }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = recentlyChangedByOthers.values.map(\.until).min() else { return }
        let delay = max(0.01, next.timeIntervalSince(now()))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.pruneExpired()
            self.scheduleExpiry()
        }
    }
}
