import CloudKit
import CoreData
import Observation

/// The CloudKit-backed sharing surface (P5-06). Never calls the container itself: every blocking NSPCKC call goes
/// through `SharingBackend` on a background queue, and the synchronous lookups the UI uses (`share(for:)`,
/// `canUpdateRecord`, so `role(for:)` and `canEdit`) read `states`, a cache refreshed off the main thread. P0-01:
/// called on the main actor, those container calls froze the UI while an export ran and the watchdog killed the app.
@MainActor
@Observable
public final class ContainerCloudSharing: CloudSharing {
    @ObservationIgnored private let backend: any SharingBackend
    @ObservationIgnored private let persistence: PersistenceController
    /// Share and permission per object, as of the last refresh. Observed, so views update when it fills.
    public private(set) var states: [NSManagedObjectID: ShareState] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false

    @ObservationIgnored private let retryDelay: Duration

    public init(persistence: PersistenceController, backend: any SharingBackend, retryDelay: Duration = .seconds(2)) {
        self.persistence = persistence
        self.backend = backend
        self.retryDelay = retryDelay
    }

    /// NSPersistentCloudKitContainer drops a request when one of the same kind is already pending
    /// (`NSCocoaErrorDomain` 134417, "cancelled because there is already a pending request"). P5-06 smoke: a purge
    /// right after launch removed the local copy but left the zone on the server, so it must be retried.
    static func isCancelledForPendingRequest(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == 134417
    }

    private func scope(of store: NSPersistentStore) -> StoreScope {
        store === persistence.sharedStore ? .shared : .private
    }

    // MARK: Cache

    public func refreshShares() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "Space")
            request.resultType = .managedObjectIDResultType
            let ids = ((try? persistence.viewContext.fetch(request)) ?? []).filter { !$0.isTemporaryID }
            let fresh = await backend.states(for: ids)
            if fresh != states { states = fresh }
        } while refreshAgain
    }

    public func forget(_ objectIDs: [NSManagedObjectID]) {
        for id in objectIDs where states[id] != nil { states[id] = nil }
    }

    // MARK: Lookups (never block)

    public func share(forObjectWith objectID: NSManagedObjectID) -> CKShare? {
        states[objectID]?.share
    }

    public func shares(in store: NSPersistentStore) throws -> [CKShare] {
        var seen = Set<CKRecord.ID>()
        return states
            .filter { $0.key.persistentStore === store }
            .compactMap(\.value.share)
            .filter { seen.insert($0.recordID).inserted }
    }

    /// The private store is always editable. A joined household is read-only until the cache knows better
    /// (fail closed), so a read-only participant never gets an edit that silently diverges (P0-01 row 15).
    public func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool {
        if objectID.persistentStore !== persistence.sharedStore { return true }
        return states[objectID]?.canUpdate ?? false
    }

    /// Not answered synchronously any more (it would block); use `fetchRecordZoneID(forObjectWith:)`.
    public func recordZoneID(forObjectWith objectID: NSManagedObjectID) -> CKRecordZone.ID? { nil }

    /// The container's answer, or the last known share when it has none (it answers "not shared" until mirroring
    /// is set up), so a leave never fails and a share is never created twice because of a cold container.
    public func fetchShare(forObjectWith objectID: NSManagedObjectID) async -> CKShare? {
        guard !objectID.isTemporaryID else { return nil }
        let state = await backend.states(for: [objectID])[objectID]
        guard let fresh = state?.share else { return states[objectID]?.share }
        if let state, states[objectID] != state { states[objectID] = state }
        return fresh
    }

    public func fetchRecordZoneID(forObjectWith objectID: NSManagedObjectID) async -> CKRecordZone.ID? {
        guard !objectID.isTemporaryID else { return nil }
        return await backend.recordZoneID(for: objectID)
    }

    // MARK: Operations

    public func share(_ objects: [NSManagedObject], to existing: CKShare?) async throws -> CKShare {
        let ids = objects.map(\.objectID)
        let share = try await backend.share(ids, to: existing.map { UncheckedSendable(value: $0) })
        return share.value
    }

    public func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare {
        let saved = try await backend.persistUpdatedShare(UncheckedSendable(value: share), in: scope(of: store))
        await refreshShares()
        return saved.value
    }

    public func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        let scope = scope(of: store)
        var attempt = 1
        while true {
            do {
                try await backend.purgeZone(zoneID, in: scope)
                return
            } catch where Self.isCancelledForPendingRequest(error) && attempt < 5 {
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    public func acceptShareInvitations(from invitations: [any ShareInvitation], into store: NSPersistentStore) async throws {
        let metadata = invitations.compactMap { $0 as? CKShare.Metadata }
        guard !metadata.isEmpty else { return }
        try await backend.acceptShareInvitations(UncheckedSendable(value: metadata), into: scope(of: store))
        await refreshShares()
    }
}
