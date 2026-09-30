import CoreData
import Foundation
import HomassyShared

/// A branch of a chain the app knows a position for: a planned store reminder region (P4-06) or the region of the
/// arrival notification the user tapped.
public struct ChainBranch: Equatable, Sendable {
    public let chainKey: String
    public let center: Coordinate

    public init(chainKey: String, center: Coordinate) {
        self.chainKey = chainKey
        self.center = center
    }
}

/// A saved store with open items, in one household.
public struct WaitingStore: Equatable, Sendable {
    public let storeID: UUID
    public let spaceID: UUID
    public let chainKey: String
    public let center: Coordinate?
    public let waiting: Int

    public init(storeID: UUID, spaceID: UUID, chainKey: String, center: Coordinate?, waiting: Int) {
        self.storeID = storeID
        self.spaceID = spaceID
        self.chainKey = chainKey
        self.center = center
        self.waiting = waiting
    }
}

/// What the shopping Live Activity is about: a household and a store or chain. `center` is where the store is (nil
/// for an activity an earlier process started when the memory lost it).
public struct ShoppingActivityTarget: Equatable, Sendable {
    public let spaceID: UUID
    public let scope: ShoppingActivityScope
    public let center: Coordinate?

    public init(spaceID: UUID, scope: ShoppingActivityScope, center: Coordinate?) {
        self.spaceID = spaceID
        self.scope = scope
        self.center = center
    }
}

/// Which store the user is at (N-04 D9 B, D10 A). Pure apart from `waitingStores`.
public enum ShoppingActivityTrigger {
    /// The same circle as the arrival reminders (P4-06).
    public static let arrivalRadius: Double = StoreReminderPlanner.regionRadius
    /// Opening the app farther than this from the activity's store ends it, and lifts a suppression.
    public static let leaveDistance: Double = 1_000

    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        StoreResult(mapItemIdentifier: "", name: "", latitude: a.latitude, longitude: a.longitude)
            .distance(toLatitude: b.latitude, longitude: b.longitude)
    }

    /// The household with saved stores with open items within 150 m (the selected household first, then the one with
    /// more open items there; ties by `spaceID`), covering every one of its stores in that circle (D11): one store →
    /// `.store`, several → `.stores`. Otherwise a known branch within 150 m of a chain with open items: that chain in
    /// the household ranked the same way.
    public static func target(position: Coordinate, stores: [WaitingStore], branches: [ChainBranch],
                              preferredSpaceID: UUID?) -> ShoppingActivityTarget? {
        func rank(_ spaceID: UUID, _ waiting: Int) -> (Int, Int, String) {
            (spaceID == preferredSpaceID ? 1 : 0, waiting, spaceID.uuidString)
        }
        func best(_ bySpace: [UUID: Int]) -> UUID? {
            bySpace.max { rank($0.key, $0.value) < rank($1.key, $1.value) }?.key
        }

        let near: [(store: WaitingStore, center: Coordinate, distance: Double)] = stores.compactMap { store in
            guard store.waiting > 0, let center = store.center else { return nil }
            let metres = distance(position, center)
            return metres <= arrivalRadius ? (store, center, metres) : nil
        }
        let nearBySpace = Dictionary(grouping: near, by: \.store.spaceID)
        if let space = best(nearBySpace.mapValues { $0.reduce(0) { $0 + $1.store.waiting } }),
           let members = nearBySpace[space]?.sorted(by: { $0.distance < $1.distance }), let nearest = members.first {
            let ids = members.map(\.store.storeID)
            let scope: ShoppingActivityScope = ids.count == 1
                ? .store(ids[0]) : .stores(ids.sorted { $0.uuidString < $1.uuidString })
            return ShoppingActivityTarget(spaceID: space, scope: scope, center: nearest.center)
        }

        let chains = Dictionary(grouping: stores.filter { $0.waiting > 0 && !$0.chainKey.isEmpty }, by: \.chainKey)
        let hits = branches.compactMap { branch -> (branch: ChainBranch, distance: Double)? in
            guard chains[branch.chainKey] != nil else { return nil }
            let metres = distance(position, branch.center)
            return metres <= arrivalRadius ? (branch, metres) : nil
        }
        guard let branch = hits.min(by: { $0.distance < $1.distance })?.branch,
              let members = chains[branch.chainKey],
              let space = best(Dictionary(grouping: members, by: \.spaceID).mapValues { $0.reduce(0) { $0 + $1.waiting } })
        else { return nil }
        return ShoppingActivityTarget(spaceID: space, scope: .chain(branch.chainKey), center: branch.center)
    }

    /// Every saved store with open items, per household: bought, undo-pending and deleted rows left out.
    @MainActor
    public static func waitingStores(in context: NSManagedObjectContext, pending: PendingDeletions) throws -> [WaitingStore] {
        let items = try context.fetchEntities(ShoppingListItem.self,
                                              where: NSPredicate(format: "isPurchased == NO AND shoppingLocation != nil"))
        var counts: [UUID: (store: ShoppingLocation, space: Space, waiting: Int)] = [:]
        for item in items where !item.isGone && !pending.contains(item.publicId) {
            guard let store = item.shoppingLocation, !store.isGone,
                  let list = item.shoppingList, !list.isGone,
                  let space = list.space, !space.isGone else { continue }
            counts[store.publicId, default: (store, space, 0)].waiting += 1
        }
        return counts.values.map { entry in
            let center = entry.store.latitude.flatMap { latitude in
                entry.store.longitude.map { Coordinate(latitude: latitude, longitude: $0) }
            }
            return WaitingStore(storeID: entry.store.publicId, spaceID: entry.space.publicId,
                                chainKey: ChainKey.make(entry.store.name), center: center, waiting: entry.waiting)
        }
    }
}
