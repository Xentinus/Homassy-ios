import CloudKit
import CoreData

/// What the app needs from a share invitation. `CKShare.Metadata` has no public initialiser,
/// so tests use a fake conforming class.
public protocol ShareInvitation: AnyObject {
    var containerIdentifier: String { get }
    var sharedZoneID: CKRecordZone.ID { get }
}

extension CKShare.Metadata: ShareInvitation {
    public var sharedZoneID: CKRecordZone.ID { share.recordID.zoneID }
}

/// The NSPersistentCloudKitContainer sharing surface Homassy uses. Main-actor bound because
/// CKShare is not Sendable.
@MainActor
public protocol CloudSharing: ShareLookup {
    /// False only for `LocalCloudSharing`: there is no CloudKit behind it (local mode).
    var isCloudBacked: Bool { get }
    func share(_ objects: [NSManagedObject], to existing: CKShare?) async throws -> CKShare
    func share(forObjectWith objectID: NSManagedObjectID) -> CKShare?
    func shares(in store: NSPersistentStore) throws -> [CKShare]
    func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool
    func recordZoneID(forObjectWith objectID: NSManagedObjectID) -> CKRecordZone.ID?
    func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare
    func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws
    func acceptShareInvitations(from invitations: [any ShareInvitation], into store: NSPersistentStore) async throws
}

extension CloudSharing {
    public var isCloudBacked: Bool { true }
    public func share(for space: Space) -> CKShare? { share(forObjectWith: space.objectID) }
}

/// Carries a non-Sendable CloudKit result from a CloudKit callback queue to the main actor.
/// It is only ever unwrapped on the main actor and never mutated in between.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}
