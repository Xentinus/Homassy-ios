import CloudKit
import CoreData
import Foundation

/// Which of the two stores a sharing call targets. The backend owns the stores, so callers on the main actor
/// never hand a non-Sendable `NSPersistentStore` across.
public enum StoreScope: Sendable, Equatable {
    case `private`, shared
}

/// What the container knows about one object: the share covering it (nil = not shared) and whether the current
/// user may change it.
public struct ShareState: @unchecked Sendable, Equatable {
    public let share: CKShare?
    public let canUpdate: Bool

    public init(share: CKShare?, canUpdate: Bool) {
        self.share = share
        self.canUpdate = canUpdate
    }

    public static func == (lhs: ShareState, rhs: ShareState) -> Bool {
        lhs.share?.recordID == rhs.share?.recordID && lhs.canUpdate == rhs.canUpdate
            && lhs.share?.currentUserParticipant?.permission == rhs.share?.currentUserParticipant?.permission
    }
}

/// The blocking NSPersistentCloudKitContainer sharing calls (P5-06). Every one of them waits for a running
/// CloudKit export on the calling thread (P0-01: the main thread froze until the watchdog killed the app), so the
/// real backend runs them on its own serial queue. `ContainerCloudSharing` is the only caller.
public protocol SharingBackend: Sendable {
    /// Share and permission for every object that still exists. Objects that are gone (deleted, purged) are left
    /// out: asking NSPCKC about them raises an Objective-C exception (P0-01 rows 17–18).
    func states(for objectIDs: [NSManagedObjectID]) async -> [NSManagedObjectID: ShareState]
    func share(_ objectIDs: [NSManagedObjectID], to existing: UncheckedSendable<CKShare>?) async throws -> UncheckedSendable<CKShare>
    func persistUpdatedShare(_ share: UncheckedSendable<CKShare>, in scope: StoreScope) async throws -> UncheckedSendable<CKShare>
    func purgeZone(_ zoneID: CKRecordZone.ID, in scope: StoreScope) async throws
    func acceptShareInvitations(_ metadata: UncheckedSendable<[CKShare.Metadata]>, into scope: StoreScope) async throws
    func recordZoneID(for objectID: NSManagedObjectID) async -> CKRecordZone.ID?
}

/// The real backend: one serial background queue, a background context for existence checks.
public final class ContainerSharingBackend: SharingBackend, @unchecked Sendable {
    // Immutable references, only used on `queue`.
    private let container: NSPersistentCloudKitContainer
    private let privateStore: NSPersistentStore
    private let sharedStore: NSPersistentStore
    private let queue = DispatchQueue(label: "app.larari.sharing", qos: .userInitiated)
    private let lookupContext: NSManagedObjectContext

    @MainActor
    public init(persistence: PersistenceController) {
        container = persistence.container
        privateStore = persistence.privateStore
        sharedStore = persistence.sharedStore
        lookupContext = persistence.container.newBackgroundContext()
    }

    private func store(_ scope: StoreScope) -> NSPersistentStore {
        scope == .private ? privateStore : sharedStore
    }

    /// Runs `work` on the sharing queue and returns its result to the caller's executor.
    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        let job = UncheckedSendable(value: work)
        let box: UncheckedSendable<T> = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: UncheckedSendable(value: try job.value())) }
                catch { continuation.resume(throwing: error) }
            }
        }
        return box.value
    }

    /// Runs a completion-handler container call on the sharing queue (the call itself blocks that thread).
    private func runCallback<T>(_ start: @escaping (@escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let job = UncheckedSendable(value: start)
        let box: UncheckedSendable<T> = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                job.value { result in
                    switch result {
                    case let .success(value): continuation.resume(returning: UncheckedSendable(value: value))
                    case let .failure(error): continuation.resume(throwing: error)
                    }
                }
            }
        }
        return box.value
    }

    /// The objects that still exist in the store (checked on the queue, in the background context).
    static func existing(_ objectIDs: [NSManagedObjectID], in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        context.performAndWait {
            context.reset()
            return objectIDs.filter { id in
                guard !id.isTemporaryID, let object = try? context.existingObject(with: id) else { return false }
                return !object.isDeleted
            }
        }
    }

    public func states(for objectIDs: [NSManagedObjectID]) async -> [NSManagedObjectID: ShareState] {
        (try? await run { [container, lookupContext] in
            let ids = Self.existing(objectIDs, in: lookupContext)
            guard !ids.isEmpty else { return [:] }
            let shares = (try? container.fetchShares(matching: ids)) ?? [:]
            var result: [NSManagedObjectID: ShareState] = [:]
            for id in ids {
                result[id] = ShareState(share: shares[id], canUpdate: container.canUpdateRecord(forManagedObjectWith: id))
            }
            return result
        }) ?? [:]
    }

    public func share(_ objectIDs: [NSManagedObjectID],
                      to existing: UncheckedSendable<CKShare>?) async throws -> UncheckedSendable<CKShare> {
        let share: CKShare = try await runCallback { [container, lookupContext] finish in
            let objects = lookupContext.performAndWait {
                objectIDs.compactMap { try? lookupContext.existingObject(with: $0) }
            }
            guard objects.count == objectIDs.count else { return finish(.failure(CKError(.unknownItem))) }
            container.share(objects, to: existing?.value) { _, share, _, error in
                if let share { finish(.success(share)) } else { finish(.failure(error ?? CKError(.internalError))) }
            }
        }
        return UncheckedSendable(value: share)
    }

    public func persistUpdatedShare(_ share: UncheckedSendable<CKShare>,
                                    in scope: StoreScope) async throws -> UncheckedSendable<CKShare> {
        let target = store(scope)
        let saved: CKShare = try await runCallback { [container] finish in
            container.persistUpdatedShare(share.value, in: target) { saved, error in
                if let saved { finish(.success(saved)) } else { finish(.failure(error ?? CKError(.internalError))) }
            }
        }
        return UncheckedSendable(value: saved)
    }

    public func purgeZone(_ zoneID: CKRecordZone.ID, in scope: StoreScope) async throws {
        let target = store(scope)
        try await runCallback { [container] (finish: @escaping @Sendable (Result<Void, Error>) -> Void) in
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: target) { _, error in
                finish(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    public func acceptShareInvitations(_ metadata: UncheckedSendable<[CKShare.Metadata]>, into scope: StoreScope) async throws {
        let target = store(scope)
        try await runCallback { [container] (finish: @escaping @Sendable (Result<Void, Error>) -> Void) in
            container.acceptShareInvitations(from: metadata.value, into: target) { _, error in
                finish(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    public func recordZoneID(for objectID: NSManagedObjectID) async -> CKRecordZone.ID? {
        try? await run { [container, lookupContext] in
            guard !Self.existing([objectID], in: lookupContext).isEmpty else { return nil }
            return container.recordID(for: objectID)?.zoneID
        }
    }
}
