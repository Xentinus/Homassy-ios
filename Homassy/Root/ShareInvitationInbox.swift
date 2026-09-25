import CloudKit
import Observation

/// Holds invitations that arrive before the services exist (cold start, account gate still checking).
@MainActor
@Observable
final class ShareInvitationInbox {
    static let shared = ShareInvitationInbox()

    private(set) var pending: [CKShare.Metadata] = []

    func receive(_ metadata: CKShare.Metadata) {
        pending.append(metadata)
    }

    func takeNext() -> CKShare.Metadata? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}
