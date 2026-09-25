import CoreData
import Foundation

public enum ImportMode {
    case asNewSpace(name: String)
    case merge(into: Space)
}

public struct EntityImportCounts: Equatable, Sendable {
    public var toCreate: Int
    public var toUpdate: Int
    public var unchanged: Int
    public var total: Int { toCreate + toUpdate + unchanged }

    public init(toCreate: Int = 0, toUpdate: Int = 0, unchanged: Int = 0) {
        self.toCreate = toCreate
        self.toUpdate = toUpdate
        self.unchanged = unchanged
    }
}

public struct ImportPreview: Equatable, Sendable {
    public let manifest: ArchiveManifest
    public let isMerge: Bool
    public let counts: [ArchiveEntity: EntityImportCounts]

    public func counts(for entity: ArchiveEntity) -> EntityImportCounts { counts[entity] ?? EntityImportCounts() }
    public var totalToCreate: Int { counts.values.reduce(0) { $0 + $1.toCreate } }
    public var totalToUpdate: Int { counts.values.reduce(0) { $0 + $1.toUpdate } }
}

public struct ImportResult {
    public let space: Space
    public let counts: [ArchiveEntity: EntityImportCounts]
}

@MainActor
public final class ArchiveImporter {
    private enum Decision<T: HomassyEntity> {
        case create(UUID)       // insert with this publicId
        case update(T)          // archive is newer: overwrite fields
        case keep(T)            // local is equal or newer: leave untouched, but map references to it
    }

    private struct Plan {
        var members: [UUID: Decision<Member>] = [:]
        var products: [UUID: Decision<Product>] = [:]
        var storageLocations: [UUID: Decision<StorageLocation>] = [:]
        var shoppingLocations: [UUID: Decision<ShoppingLocation>] = [:]
        var shoppingLists: [UUID: Decision<ShoppingList>] = [:]
        var inventoryItems: [UUID: Decision<InventoryItem>] = [:]
        var consumptionLogs: [UUID: Decision<ConsumptionLog>] = [:]
        var inventoryEvents: [UUID: Decision<InventoryEvent>] = [:]
        var shoppingListItems: [UUID: Decision<ShoppingListItem>] = [:]
        var counts: [ArchiveEntity: EntityImportCounts] = [:]
    }

    private let persistence: PersistenceController
    private let spaceStore: SpaceStore
    private let userRecordName: String
    private let now: () -> Date
    private var context: NSManagedObjectContext { persistence.viewContext }

    /// Test hook: runs after each collection is applied and before the save.
    var afterApplying: ((ArchiveEntity) throws -> Void)?

    public init(persistence: PersistenceController, spaceStore: SpaceStore, userRecordName: String,
                now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        self.spaceStore = spaceStore
        self.userRecordName = userRecordName
        self.now = now
    }

    /// Reads and validates the archive and reports what an import would do. Writes nothing.
    public func preview(url: URL, mergeInto target: Space? = nil) throws -> ImportPreview {
        let loaded = try ArchivePackage.read(url)
        try ArchiveValidator.validate(loaded.contents.data)
        let plan = try makePlan(for: loaded.contents.data, target: target)
        return ImportPreview(manifest: loaded.contents.manifest, isMerge: target != nil, counts: plan.counts)
    }

    /// Applies the archive in one save. Any error rolls the context back, so nothing is written.
    @discardableResult
    public func importArchive(url: URL, mode: ImportMode) throws -> ImportResult {
        guard !context.hasChanges else { throw ArchiveError.unsavedChanges }
        let loaded = try ArchivePackage.read(url)
        let data = loaded.contents.data
        try ArchiveValidator.validate(data)
        do {
            let space: Space
            let plan: Plan
            switch mode {
            case .asNewSpace(let name):
                space = try makeSpace(named: name)
                plan = try makePlan(for: data, target: nil)
            case .merge(let target):
                space = target
                plan = try makePlan(for: data, target: target)
            }
            try apply(data, images: loaded.images, plan: plan, in: space)
            try context.save()
            return ImportResult(space: space, counts: plan.counts)
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Planning

    private func makePlan(for data: ArchiveData, target: Space?) throws -> Plan {
        var plan = Plan()
        plan.members = try decide(Member.self, data.members, target: target, entity: .members,
                                  counts: &plan.counts) { $0.space == target }
        plan.products = try decide(Product.self, data.products, target: target, entity: .products,
                                   counts: &plan.counts) { $0.space == target }
        plan.storageLocations = try decide(StorageLocation.self, data.storageLocations, target: target,
                                           entity: .storageLocations, counts: &plan.counts) { $0.space == target }
        plan.shoppingLocations = try decide(ShoppingLocation.self, data.shoppingLocations, target: target,
                                            entity: .shoppingLocations, counts: &plan.counts) { $0.space == target }
        plan.shoppingLists = try decide(ShoppingList.self, data.shoppingLists, target: target,
                                        entity: .shoppingLists, counts: &plan.counts) { $0.space == target }
        plan.inventoryItems = try decide(InventoryItem.self, data.inventoryItems, target: target,
                                         entity: .inventoryItems, counts: &plan.counts) { $0.product?.space == target }
        plan.consumptionLogs = try decide(ConsumptionLog.self, data.consumptionLogs, target: target,
                                          entity: .consumptionLogs,
                                          counts: &plan.counts) { $0.inventoryItem?.product?.space == target }
        plan.inventoryEvents = try decide(InventoryEvent.self, data.inventoryEvents, target: target,
                                          entity: .inventoryEvents, counts: &plan.counts) { $0.product?.space == target }
        plan.shoppingListItems = try decide(ShoppingListItem.self, data.shoppingListItems, target: target,
                                            entity: .shoppingListItems, counts: &plan.counts) { $0.shoppingList?.space == target }
        return plan
    }

    private func decide<T: HomassyEntity, R: ArchiveRecord>(
        _ type: T.Type, _ records: [R], target: Space?, entity: ArchiveEntity,
        counts: inout [ArchiveEntity: EntityImportCounts], belongsToTarget: (T) -> Bool
    ) throws -> [UUID: Decision<T>] {
        var tally = EntityImportCounts()
        var decisions: [UUID: Decision<T>] = [:]
        defer { counts[entity] = tally }

        guard target != nil else {
            for record in records {
                decisions[record.publicId] = .create(UUID())
                tally.toCreate += 1
            }
            return decisions
        }

        let existing = Dictionary(grouping: try fetch(type, publicIds: records.map(\.publicId)), by: \.publicId)
        for record in records {
            let matches = existing[record.publicId] ?? []
            if let local = matches.first(where: belongsToTarget) {
                if ArchiveDate.milliseconds(record.updatedAt) > ArchiveDate.milliseconds(local.updatedAt) {
                    decisions[record.publicId] = .update(local)
                    tally.toUpdate += 1
                } else {
                    decisions[record.publicId] = .keep(local)
                    tally.unchanged += 1
                }
            } else {
                // Keep the archive's id unless another space already uses it (ids are global).
                decisions[record.publicId] = .create(matches.isEmpty ? record.publicId : UUID())
                tally.toCreate += 1
            }
        }
        return decisions
    }

    private func fetch<T: HomassyEntity>(_ type: T.Type, publicIds: [UUID]) throws -> [T] {
        guard !publicIds.isEmpty else { return [] }
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "publicId IN %@", publicIds.map { $0 as NSUUID } as NSArray)
        return try context.fetch(request)
    }

    // MARK: Applying

    private func makeSpace(named name: String) throws -> Space {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.nameRequired }
        let orders: [Int] = try spaceStore.allSpaces().map { numericCast($0.sortOrder) }
        let space = Space(context: context)
        context.assign(space, to: persistence.privateStore)
        space.publicId = UUID()
        space.name = trimmed
        space.kind = .household
        space.sortOrder = numericCast((orders.max() ?? 0) + 1)
        space.stamp(by: userRecordName, now: now())
        return space
    }

    private func materialize<T: HomassyEntity>(_ decision: Decision<T>?, in space: Space) throws -> (object: T, write: Bool) {
        switch decision {
        case .create(let id)?:
            let object = spaceStore.insert(T.self, in: space, by: userRecordName)
            object.publicId = id
            return (object, true)
        case .update(let object)?:
            return (object, true)
        case .keep(let object)?:
            return (object, false)
        case nil:
            throw ArchiveError.corrupted("record without a plan")
        }
    }

    private func copyMeta<T: HomassyEntity, R: ArchiveRecord>(_ record: R, to object: T) {
        object.createdAt = record.createdAt
        object.updatedAt = record.updatedAt
        object.createdBy = record.createdBy
        object.updatedBy = record.updatedBy
    }

    private func required<T>(_ value: T?, _ entity: ArchiveEntity, _ record: UUID, _ field: String) throws -> T {
        guard let value else { throw ArchiveError.brokenReference(entity: entity, publicId: record, field: field) }
        return value
    }

    private func apply(_ data: ArchiveData, images: [String: Data], plan: Plan, in space: Space) throws {
        func image(_ reference: String?) throws -> Data? {
            guard let reference else { return nil }
            guard let bytes = images[reference] else { throw ArchiveError.missingImage(reference) }
            return bytes
        }

        for dto in data.members {
            let (member, write) = try materialize(plan.members[dto.publicId], in: space)
            guard write else { continue }
            copyMeta(dto, to: member)
            member.space = space
            member.userRecordName = dto.userRecordName
            member.displayName = dto.displayName
            member.colorSeed = dto.colorSeed
            member.avatar = try image(dto.avatar)
        }
        try afterApplying?(.members)

        var products: [UUID: Product] = [:]
        for dto in data.products {
            let (product, write) = try materialize(plan.products[dto.publicId], in: space)
            products[dto.publicId] = product
            guard write else { continue }
            copyMeta(dto, to: product)
            product.space = space
            product.name = dto.name
            product.brand = dto.brand
            product.category = dto.category
            product.barcode = dto.barcode
            product.defaultUnit = dto.defaultUnit
            product.isFavorite = dto.isFavorite
            product.notes = dto.notes
            product.image = try image(dto.image)
            product.url = dto.url
        }
        try afterApplying?(.products)

        var storage: [UUID: StorageLocation] = [:]
        for dto in data.storageLocations {
            let (location, write) = try materialize(plan.storageLocations[dto.publicId], in: space)
            storage[dto.publicId] = location
            guard write else { continue }
            copyMeta(dto, to: location)
            location.space = space
            location.name = dto.name
            location.color = dto.color
            location.sortOrder = numericCast(dto.sortOrder)
            location.isFreezer = dto.isFreezer
        }
        try afterApplying?(.storageLocations)

        var stores: [UUID: ShoppingLocation] = [:]
        for dto in data.shoppingLocations {
            let (store, write) = try materialize(plan.shoppingLocations[dto.publicId], in: space)
            stores[dto.publicId] = store
            guard write else { continue }
            copyMeta(dto, to: store)
            store.space = space
            store.mapItemIdentifier = dto.mapItemIdentifier
            store.name = dto.name
            store.latitude = dto.latitude
            store.longitude = dto.longitude
            store.lastUsedAt = dto.lastUsedAt
        }
        try afterApplying?(.shoppingLocations)

        var lists: [UUID: ShoppingList] = [:]
        for dto in data.shoppingLists {
            let (list, write) = try materialize(plan.shoppingLists[dto.publicId], in: space)
            lists[dto.publicId] = list
            guard write else { continue }
            copyMeta(dto, to: list)
            list.space = space
            list.name = dto.name
            list.color = dto.color
            list.sortOrder = numericCast(dto.sortOrder)
        }
        try afterApplying?(.shoppingLists)

        var items: [UUID: InventoryItem] = [:]
        for dto in data.inventoryItems {
            let (item, write) = try materialize(plan.inventoryItems[dto.publicId], in: space)
            items[dto.publicId] = item
            guard write else { continue }
            copyMeta(dto, to: item)
            item.product = try required(products[dto.product], .inventoryItems, dto.publicId, "product")
            item.quantity = dto.quantity.value
            item.unit = dto.unit
            item.expiresAt = dto.expiresAt
            item.purchasedAt = dto.purchasedAt
            item.price = dto.price?.value
            item.currency = dto.currency
            item.isFullyConsumed = dto.isFullyConsumed
            item.consumedAt = dto.consumedAt
            item.storageLocation = dto.storageLocation.flatMap { storage[$0] }
            item.shoppingLocation = dto.shoppingLocation.flatMap { stores[$0] }
        }
        try afterApplying?(.inventoryItems)

        for dto in data.consumptionLogs {
            let (log, write) = try materialize(plan.consumptionLogs[dto.publicId], in: space)
            guard write else { continue }
            copyMeta(dto, to: log)
            log.inventoryItem = try required(items[dto.inventoryItem], .consumptionLogs, dto.publicId, "inventoryItem")
            log.quantity = dto.quantity.value
            log.remaining = dto.remaining.value
            log.consumedAt = dto.consumedAt
        }
        try afterApplying?(.consumptionLogs)

        for dto in data.inventoryEvents {
            let (event, write) = try materialize(plan.inventoryEvents[dto.publicId], in: space)
            guard write else { continue }
            copyMeta(dto, to: event)
            event.product = try required(products[dto.product], .inventoryEvents, dto.publicId, "product")
            event.inventoryItem = dto.inventoryItem.flatMap { items[$0] }
            event.kind = dto.kind
            event.quantity = dto.quantity.value
            event.unit = dto.unit
            event.fromLocationName = dto.fromLocationName
            event.toLocationName = dto.toLocationName
            event.occurredAt = dto.occurredAt
        }
        try afterApplying?(.inventoryEvents)

        for dto in data.shoppingListItems {
            let (item, write) = try materialize(plan.shoppingListItems[dto.publicId], in: space)
            guard write else { continue }
            copyMeta(dto, to: item)
            item.shoppingList = try required(lists[dto.list], .shoppingListItems, dto.publicId, "list")
            item.product = dto.product.flatMap { products[$0] }
            item.customName = dto.customName
            item.quantity = dto.quantity.value
            item.unit = dto.unit
            item.note = dto.note
            item.deadline = dto.deadline
            item.isPurchased = dto.isPurchased
            item.purchasedAt = dto.purchasedAt
            item.sortOrder = numericCast(dto.sortOrder)
            item.shoppingLocation = dto.shoppingLocation.flatMap { stores[$0] }
        }
        try afterApplying?(.shoppingListItems)
    }
}
