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

/// The NSPersistentCloudKitContainer sharing surface Larari uses. Main-actor bound because
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

    // P5-06 (P0-01 findings). The sync lookups above must never block: the CloudKit-backed implementation answers
    // them from a cache that these refresh off the main thread.

    /// Re-reads shares and permissions for every space. Called at launch, after remote changes and when the app
    /// becomes active.
    func refreshShares() async
    /// A fresh lookup for decisions that must not trust a cache (create, leave, delete).
    func fetchShare(forObjectWith objectID: NSManagedObjectID) async -> CKShare?
    /// A fresh zone lookup (the DEBUG zone check).
    func fetchRecordZoneID(forObjectWith objectID: NSManagedObjectID) async -> CKRecordZone.ID?
    /// Drops purged or deleted objects, so nothing asks the container about them again.
    func forget(_ objectIDs: [NSManagedObjectID])
}

extension CloudSharing {
    public var isCloudBacked: Bool { true }
    public func share(for space: Space) -> CKShare? { share(forObjectWith: space.objectID) }

    public func refreshShares() async {}
    public func fetchShare(forObjectWith objectID: NSManagedObjectID) async -> CKShare? { share(forObjectWith: objectID) }
    public func fetchRecordZoneID(forObjectWith objectID: NSManagedObjectID) async -> CKRecordZone.ID? {
        recordZoneID(forObjectWith: objectID)
    }
    public func forget(_ objectIDs: [NSManagedObjectID]) {}
}

/// Carries a non-Sendable CloudKit value between the main actor and the sharing queue.
/// It is never mutated in between.
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public let value: Value
    public init(value: Value) { self.value = value }
}
