import CloudKit
import CoreData
import Foundation
import Observation

public enum ShareAcceptanceFailure: Error, Equatable, LocalizedError {
    case wrongContainer
    case cloudKit(code: Int)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .wrongContainer:
            return String(localized: "share.accept.error.wrongContainer", defaultValue: "This invitation belongs to a different app.", bundle: .module)
        case .timedOut:
            return String(localized: "share.accept.error.timedOut", defaultValue: "The household hasn't arrived yet. Keep Larari open and try again.", bundle: .module)
        case let .cloudKit(code):
            switch CKError.Code(rawValue: code) {
            case .networkUnavailable?, .networkFailure?, .serviceUnavailable?, .requestRateLimited?:
                return String(localized: "share.accept.error.network", defaultValue: "Couldn't reach iCloud. Check your connection and try again.", bundle: .module)
            case .unknownItem?, .participantMayNeedVerification?:
                return String(localized: "share.accept.error.invalid", defaultValue: "This invitation is no longer valid. Ask for a new link.", bundle: .module)
            default:
                return String(localized: "share.accept.error.generic", defaultValue: "Couldn't join the household (error \(code)). Try again.", bundle: .module)
            }
        }
    }
}

@MainActor
@Observable
public final class ShareAcceptanceModel {
    public enum State: Equatable {
        case idle
        case accepting
        case waitingForData
        case accepted(spacePublicId: UUID)
        case failed(ShareAcceptanceFailure)
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let cloud: any CloudSharing
    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var lastInvitation: (any ShareInvitation)?

    public init(persistence: PersistenceController, cloud: any CloudSharing,
                containerIdentifier: String = "iCloud.app.larari",
                pollInterval: Duration = .seconds(1), timeout: Duration = .seconds(90)) {
        self.persistence = persistence
        self.cloud = cloud
        self.containerIdentifier = containerIdentifier
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    public var isBusy: Bool { state == .accepting || state == .waitingForData }

    public func accept(_ invitation: any ShareInvitation) async {
        lastInvitation = invitation
        guard invitation.containerIdentifier == containerIdentifier else {
            state = .failed(.wrongContainer)
            return
        }
        let zoneID = invitation.sharedZoneID
        if let id = joinedSpaceID(in: zoneID) {
            state = .accepted(spacePublicId: id)
            return
        }

        state = .accepting
        do {
            try await cloud.acceptShareInvitations(from: [invitation], into: persistence.sharedStore)
        } catch {
            state = .failed(Self.failure(from: error))
            return
        }

        // Accepting only registers the share; the zone's records arrive with the next import.
        state = .waitingForData
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if let id = joinedSpaceID(in: zoneID) {
                state = .accepted(spacePublicId: id)
                return
            }
            if clock.now >= deadline {
                state = .failed(.timedOut)
                return
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                state = .idle          // cancelled
                return
            }
        }
    }

    public func retry() async {
        guard let lastInvitation else { return }
        await accept(lastInvitation)
    }

    public func reset() {
        state = .idle
        lastInvitation = nil
    }

    private func joinedSpaceID(in zoneID: CKRecordZone.ID) -> UUID? {
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.affectedStores = [persistence.sharedStore]
        guard let spaces = try? persistence.viewContext.fetch(request) else { return nil }
        return spaces.first { cloud.share(for: $0)?.recordID.zoneID == zoneID }?.publicId
    }

    static func failure(from error: Error) -> ShareAcceptanceFailure {
        if let ckError = error as? CKError { return .cloudKit(code: ckError.errorCode) }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == CKErrorDomain {
            return .cloudKit(code: underlying.code)
        }
        return .cloudKit(code: nsError.code)
    }
}
