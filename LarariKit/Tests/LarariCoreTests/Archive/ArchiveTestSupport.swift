import CloudKit
import CoreData
import Foundation
@testable import LarariCore

struct ArchiveNoShares: ShareLookup {
    @MainActor func share(for space: Space) -> CKShare? { nil }
}

/// Handles to the objects `seedHousehold` creates, so tests can assert on them.
@MainActor
struct SeededHousehold {
    let space: Space
    let owner: Member
    let anna: Member
    let milk: Product
    let kefir: Product
    let flour: Product
    let salt: Product
    let fridge: StorageLocation
    let spar: ShoppingLocation
    let weekly: ShoppingList
    let milkItem: InventoryItem
    let flourItem: InventoryItem
    let milkLog: ConsumptionLog
    /// History of `milkItem`.
    let milkAddedEvent: InventoryEvent
    /// History of a milk stock item that was deleted, so it has no stock item.
    let milkDeletedEvent: InventoryEvent
    let milkListItem: ShoppingListItem
    let breadListItem: ShoppingListItem
    /// Bytes shared by `milk` and `kefir`.
    let sharedPhoto: Data
    /// Bytes used only by `flour`.
    let flourPhoto: Data
}

@MainActor
final class ArchiveTestStack {
    let persistence: PersistenceController
    let spaceStore: SpaceStore
    let user = "_tester"
    var context: NSManagedObjectContext { persistence.viewContext }

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        spaceStore = SpaceStore(persistence: persistence, sharing: ArchiveNoShares())
    }

    static func date(_ text: String) -> Date {
        guard let date = ArchiveDate.parse(text) else { preconditionFailure("bad test date \(text)") }
        return date
    }

    static func decimal(_ text: String) -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            preconditionFailure("bad test decimal \(text)")
        }
        return value
    }

    /// A household in the private store, not shared, like one created before P5 shares it.
    func makeSpace(name: String, kind: SpaceKind = .household) -> Space {
        let space = Space(context: context)
        context.assign(space, to: persistence.privateStore)
        space.publicId = UUID()
        space.name = name
        space.kind = kind
        space.sortOrder = 1
        space.stamp(by: user)
        return space
    }

    func insert<T: LarariEntity>(_ type: T.Type, in space: Space,
                                  at date: Date = ArchiveTestStack.date("2026-09-01T12:00:00+02:00")) -> T {
        let object = spaceStore.insert(type, in: space, by: user)
        object.createdAt = date
        object.updatedAt = date
        return object
    }

    func fetch<T: LarariEntity>(_ type: T.Type, _ format: String, _ arguments: any CVarArg...) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: format, argumentArray: arguments)
        return try context.fetch(request).sorted { $0.publicId.uuidString < $1.publicId.uuidString }
    }

    func count<T: LarariEntity>(_ type: T.Type) throws -> Int {
        try context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))
    }

    @discardableResult
    func seedHousehold(name: String = "Otthon") throws -> SeededHousehold {
        let space = makeSpace(name: name)
        let sharedPhoto = Data(repeating: 0xAB, count: 2048)
        let flourPhoto = Data(repeating: 0xCD, count: 1024)

        let owner = insert(Member.self, in: space)
        owner.space = space
        owner.userRecordName = "_owner"
        owner.displayName = "Béla"
        owner.colorSeed = "_owner"
        let anna = insert(Member.self, in: space)
        anna.space = space
        anna.userRecordName = "_anna"
        anna.displayName = "Anna"
        anna.colorSeed = "_anna"

        func product(_ name: String, unit: MeasureUnit, image: Data?) -> Product {
            let product = insert(Product.self, in: space)
            product.space = space
            product.name = name
            product.defaultUnit = unit
            product.image = image
            return product
        }
        let milk = product("Tej", unit: .liter, image: sharedPhoto)
        milk.url = "https://www.mizo.hu/termekek/tej"
        let kefir = product("Kefir", unit: .liter, image: sharedPhoto)
        let flour = product("Liszt", unit: .kilogram, image: flourPhoto)
        let salt = product("Só", unit: .kilogram, image: nil)

        let fridge = insert(StorageLocation.self, in: space)
        fridge.space = space
        fridge.name = "Hűtő"
        fridge.sortOrder = 0

        let spar = insert(ShoppingLocation.self, in: space)
        spar.space = space
        spar.name = "Spar Market"
        spar.mapItemIdentifier = "I6FD7682FD36BB3BE"
        spar.latitude = 47.4979
        spar.longitude = 19.0402

        let milkItem = insert(InventoryItem.self, in: space)
        milkItem.product = milk
        milkItem.quantity = Self.decimal("1.5")
        milkItem.unit = .liter
        milkItem.storageLocation = fridge
        milkItem.shoppingLocation = spar
        milkItem.price = Self.decimal("459")
        milkItem.currency = "HUF"
        let flourItem = insert(InventoryItem.self, in: space)
        flourItem.product = flour
        flourItem.quantity = Self.decimal("0.1")
        flourItem.unit = .kilogram

        let milkLog = insert(ConsumptionLog.self, in: space)
        milkLog.inventoryItem = milkItem
        milkLog.quantity = Self.decimal("0.5")
        milkLog.remaining = Self.decimal("1.5")

        let milkAddedEvent = insert(InventoryEvent.self, in: space)
        milkAddedEvent.product = milk
        milkAddedEvent.inventoryItem = milkItem
        milkAddedEvent.kind = .added
        milkAddedEvent.quantity = 2
        milkAddedEvent.unit = .liter
        milkAddedEvent.toLocationName = "Hűtő"
        milkAddedEvent.occurredAt = Self.date("2026-09-01T12:00:00+02:00")
        let milkDeletedEvent = insert(InventoryEvent.self, in: space)
        milkDeletedEvent.product = milk
        milkDeletedEvent.kind = .deleted
        milkDeletedEvent.quantity = 1
        milkDeletedEvent.unit = .liter
        milkDeletedEvent.fromLocationName = "Hűtő"
        milkDeletedEvent.occurredAt = Self.date("2026-08-30T20:00:00+02:00")

        let weekly = insert(ShoppingList.self, in: space)
        weekly.space = space
        weekly.name = "Heti bevásárlás"
        weekly.sortOrder = 0
        let milkListItem = insert(ShoppingListItem.self, in: space)
        milkListItem.shoppingList = weekly
        milkListItem.product = milk
        milkListItem.quantity = 2
        milkListItem.unit = .liter
        milkListItem.sortOrder = 0
        let breadListItem = insert(ShoppingListItem.self, in: space)
        breadListItem.shoppingList = weekly
        breadListItem.customName = "Kenyér"
        breadListItem.quantity = 1
        breadListItem.unit = .piece
        breadListItem.sortOrder = 1

        try context.save()
        return SeededHousehold(space: space, owner: owner, anna: anna, milk: milk, kefir: kefir,
                               flour: flour, salt: salt, fridge: fridge, spar: spar, weekly: weekly,
                               milkItem: milkItem, flourItem: flourItem, milkLog: milkLog,
                               milkAddedEvent: milkAddedEvent, milkDeletedEvent: milkDeletedEvent,
                               milkListItem: milkListItem, breadListItem: breadListItem,
                               sharedPhoto: sharedPhoto, flourPhoto: flourPhoto)
    }

    func temporaryURL(_ name: String = "test-\(UUID().uuidString).larari") -> URL {
        FileManager.default.temporaryDirectory.appending(path: name)
    }
}
