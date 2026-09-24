import CloudKit
import Foundation

/// Reads the real iCloud account status. Needs the iCloud entitlement, so the app uses it only when built
/// with CLOUDKIT_ENABLED (C-01). No test calls it.
public struct CloudKitAccountStatus: AccountStatusProviding {
    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: containerIdentifier).accountStatus()
    }

    public func userRecordName() async throws -> String {
        try await CKContainer(identifier: containerIdentifier).userRecordID().recordName
    }
}
