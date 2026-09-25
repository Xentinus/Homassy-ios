import CloudKit
import CoreData
import Foundation
@testable import HomassyCore

struct ShoppingNoShares: ShareLookup {
    @MainActor func share(for space: Space) -> CKShare? { nil }
}

/// A settable clock for services that take `now:`. Deliberately not actor-isolated, so the
/// `{ clock.date }` closure handed to services is a plain `() -> Date`.
final class TestNow {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance(seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
final class ShoppingTestStack {
    let persistence: PersistenceController
    let spaceStore: SpaceStore
    let user = "_shopper"
    let now = TestNow(Date(timeIntervalSince1970: 1_790_000_000))
    let space: Space
    let service: ShoppingService
    let inventory: InventoryService
    let pending = PendingDeletions()
    var context: NSManagedObjectContext { persistence.viewContext }

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        spaceStore = SpaceStore(persistence: persistence, sharing: ShoppingNoShares())
        space = try spaceStore.bootstrapPersonalSpace(userRecordName: user)
        let clock = now
        service = ShoppingService(spaceStore: spaceStore, context: persistence.viewContext, userRecordName: user,
                                  now: { clock.date })
        inventory = InventoryService(spaceStore: spaceStore, context: persistence.viewContext, userRecordName: user,
                                     defaultCurrency: "HUF", now: { clock.date })
        try context.save()
    }

    /// A second space in the private store, for cross-space checks.
    func makeOtherSpace(name: String = "Másik") throws -> Space {
        let other = Space(context: context)
        context.assign(other, to: persistence.privateStore)
        other.publicId = UUID()
        other.name = name
        other.kind = .household
        other.sortOrder = 5
        other.stamp(by: user)
        try context.save()
        return other
    }

    @discardableResult
    func makeProduct(_ name: String, unit: MeasureUnit = .piece, barcode: String? = nil,
                     favorite: Bool = false, in target: Space? = nil) throws -> Product {
        let owner = target ?? space
        let product = spaceStore.insert(Product.self, in: owner, by: user)
        product.space = owner
        product.name = name
        product.defaultUnit = unit
        product.barcode = barcode
        product.isFavorite = favorite
        try context.save()
        return product
    }

    @discardableResult
    func makeStore(_ name: String, identifier: String = UUID().uuidString, in target: Space? = nil) throws -> ShoppingLocation {
        let owner = target ?? space
        let store = spaceStore.insert(ShoppingLocation.self, in: owner, by: user)
        store.space = owner
        store.name = name
        store.mapItemIdentifier = identifier
        try context.save()
        return store
    }

    @discardableResult
    func makeLocation(_ name: String, in target: Space? = nil) throws -> StorageLocation {
        let owner = target ?? space
        let location = spaceStore.insert(StorageLocation.self, in: owner, by: user)
        location.space = owner
        location.name = name
        try context.save()
        return location
    }

    func count<T: HomassyEntity>(_ type: T.Type) throws -> Int {
        try context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))
    }
}
