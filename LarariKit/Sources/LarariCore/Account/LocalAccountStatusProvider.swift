import CloudKit
import Foundation

/// Local mode (no CLOUDKIT_ENABLED): there is no iCloud entitlement, so CloudKit is never asked.
/// The gate always passes, and every object is stamped with a fixed developer record name.
/// C-01 rewrites these stamps to the real record name when it migrates the local store.
public struct LocalAccountStatusProvider: AccountStatusProviding {
    public static let userRecordName = "_localDeveloper"

    public init() {}

    public func accountStatus() async throws -> CKAccountStatus { .available }

    public func userRecordName() async throws -> String { Self.userRecordName }
}
