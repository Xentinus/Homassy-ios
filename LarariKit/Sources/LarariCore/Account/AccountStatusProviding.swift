import CloudKit
import Foundation

public enum AccountState: Equatable, Sendable {
    case checking, available, noAccount, restricted, temporarilyUnavailable, couldNotDetermine
}

/// Where the account status comes from: CloudKit in the app, a fake in tests.
public protocol AccountStatusProviding: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func userRecordName() async throws -> String
}
