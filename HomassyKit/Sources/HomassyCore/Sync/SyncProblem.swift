import CloudKit
import Foundation

public enum SyncProblem: Sendable, Equatable {
    case quotaExceeded(isOwner: Bool)
    case network
    case notAuthenticated
    case zoneGone(ZoneReference?)
    case other(code: Int)

    public static func classify(_ failure: SyncFailureInfo, isPrivateStore: Bool) -> SyncProblem {
        guard failure.isCloudKit else { return .other(code: failure.code) }
        let codes = failure.code == CKError.Code.partialFailure.rawValue ? failure.partialCodes : [failure.code]
        let problems = codes.compactMap { map(code: $0, zone: failure.affectedZones.first, isPrivateStore: isPrivateStore) }
        return problems.max { $0.priority < $1.priority } ?? .other(code: failure.code)
    }

    private static func map(code: Int, zone: ZoneReference?, isPrivateStore: Bool) -> SyncProblem? {
        switch CKError.Code(rawValue: code) {
        case .quotaExceeded?:
            return .quotaExceeded(isOwner: isPrivateStore)
        case .notAuthenticated?, .accountTemporarilyUnavailable?:
            return .notAuthenticated
        case .zoneNotFound?, .userDeletedZone?:
            return isPrivateStore ? .other(code: code) : .zoneGone(zone)
        case .networkUnavailable?, .networkFailure?, .serviceUnavailable?, .requestRateLimited?, .zoneBusy?:
            return .network
        case .partialFailure?:
            return nil
        default:
            return .other(code: code)
        }
    }

    var priority: Int {
        switch self {
        case .quotaExceeded: 5
        case .notAuthenticated: 4
        case .zoneGone: 3
        case .network: 2
        case .other: 1
        }
    }

    /// Transient problems become persistent only by repetition or duration.
    public var healsOnItsOwn: Bool {
        switch self {
        case .network, .other: true
        case .quotaExceeded, .notAuthenticated, .zoneGone: false
        }
    }

    public var message: String {
        switch self {
        case .quotaExceeded(isOwner: true):
            String(localized: "sync.problem.quota.owner", defaultValue: "Your iCloud storage is full, so this household can't sync. Free up space or upgrade your iCloud storage.", bundle: .module)
        case .quotaExceeded(isOwner: false):
            String(localized: "sync.problem.quota.participant", defaultValue: "This household isn't syncing because its owner's iCloud storage is full.", bundle: .module)
        case .network:
            String(localized: "sync.problem.network", defaultValue: "Can't reach iCloud. Changes are saved on this device and will sync when you're back online.", bundle: .module)
        case .notAuthenticated:
            String(localized: "sync.problem.notAuthenticated", defaultValue: "You're signed out of iCloud. Sign in to keep syncing.", bundle: .module)
        case .zoneGone:
            String(localized: "sync.problem.zoneGone", defaultValue: "This household is no longer available. The owner may have deleted it or removed you.", bundle: .module)
        case let .other(code):
            String(localized: "sync.problem.other", defaultValue: "iCloud sync failed (error \(code)). Homassy will keep trying.", bundle: .module)
        }
    }
}
