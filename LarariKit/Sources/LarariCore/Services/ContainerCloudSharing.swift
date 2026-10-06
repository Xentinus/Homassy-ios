import CloudKit
import CoreData

@MainActor
public final class ContainerCloudSharing: CloudSharing {
    public let container: NSPersistentCloudKitContainer

    public init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }

    public func share(_ objects: [NSManagedObject], to existing: CKShare?) async throws -> CKShare {
        let box: UncheckedSendable<CKShare> = try await withCheckedThrowingContinuation { continuation in
            container.share(objects, to: existing) { @Sendable _, share, _, error in
                if let share {
                    continuation.resume(returning: UncheckedSendable(value: share))
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
        return box.value
    }

    public func share(forObjectWith objectID: NSManagedObjectID) -> CKShare? {
        guard !objectID.isTemporaryID else { return nil }
        return (try? container.fetchShares(matching: [objectID]))?[objectID]
    }

    public func shares(in store: NSPersistentStore) throws -> [CKShare] {
        try container.fetchShares(in: store)
    }

    public func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: objectID)
    }

    public func recordZoneID(forObjectWith objectID: NSManagedObjectID) -> CKRecordZone.ID? {
        container.recordID(for: objectID)?.zoneID
    }

    public func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare {
        let box: UncheckedSendable<CKShare> = try await withCheckedThrowingContinuation { continuation in
            container.persistUpdatedShare(share, in: store) { @Sendable saved, error in
                if let saved {
                    continuation.resume(returning: UncheckedSendable(value: saved))
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
        return box.value
    }

    public func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { @Sendable _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    public func acceptShareInvitations(from invitations: [any ShareInvitation], into store: NSPersistentStore) async throws {
        let metadata = invitations.compactMap { $0 as? CKShare.Metadata }
        guard !metadata.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: metadata, into: store) { @Sendable _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
