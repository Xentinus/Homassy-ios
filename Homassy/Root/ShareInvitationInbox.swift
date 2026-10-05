import CloudKit
import Foundation
import Observation

/// Holds invitations that arrive before the services exist (cold start, account gate still checking). With several
/// iPad windows (N-03), the window that takes an invitation owns it: only that window shows the joining capsule and
/// any failure, and only that window switches to the joined household.
@MainActor
@Observable
final class ShareInvitationInbox {
    static let shared = ShareInvitationInbox()

    private(set) var pending: [CKShare.Metadata] = []
    /// The `RootView` window id that is accepting the current invitation; nil when none is, or its window closed.
    var owner: UUID?

    func receive(_ metadata: CKShare.Metadata) {
        pending.append(metadata)
    }

    func takeNext() -> CKShare.Metadata? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}
