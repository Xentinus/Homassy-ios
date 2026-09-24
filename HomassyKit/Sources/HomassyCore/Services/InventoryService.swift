import CoreData
import Foundation

/// The only writer of `InventoryItem`, `ConsumptionLog` and `InventoryEvent`.
/// Every stock action records one `InventoryEvent` (README "Inventory history").
@MainActor
public final class InventoryService {
    private let spaceStore: SpaceStore
    public let context: NSManagedObjectContext
    private let userRecordName: String
    private let canEditSpace: @MainActor (Space) -> Bool
    public let calendar: Calendar
    public let defaultCurrency: String
    private let now: @MainActor () -> Date

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                calendar: Calendar = .current,
                defaultCurrency: String = Locale.current.currency?.identifier ?? "EUR",
                now: @escaping @MainActor () -> Date = { .now }) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        self.canEditSpace = canEdit
        self.calendar = calendar
        self.defaultCurrency = defaultCurrency
        self.now = now
    }

    public func currentDate() -> Date { now() }
    public func canEdit(_ space: Space) -> Bool { canEditSpace(space) }
    public func space(of item: InventoryItem) -> Space? { item.product?.space }

    // MARK: Adding and editing

    @discardableResult
    public func addStock(product: Product, quantity: Decimal, unit: MeasureUnit, expiresAt: Date?, purchasedAt: Date?,
                         price: Decimal?, currency: String?, storageLocation: StorageLocation?,
                         shoppingLocation: ShoppingLocation?) throws -> InventoryItem {
        guard !product.isGone, let space = product.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        try validate(quantity: quantity, expiresAt: expiresAt, purchasedAt: purchasedAt)
        try ensure(storageLocation, isIn: space)
        try ensure(shoppingLocation, isIn: space)

        let item = spaceStore.insert(InventoryItem.self, in: space, by: userRecordName)
        item.product = product
        item.quantity = quantity
        item.unit = unit
        item.expiresAt = expiresAt
        item.purchasedAt = purchasedAt
        item.price = price
        item.currency = currency?.nilIfBlank ?? defaultCurrency
        item.isFullyConsumed = false
        item.consumedAt = nil
        item.storageLocation = storageLocation
        item.shoppingLocation = shoppingLocation
        record(.added, for: item, in: space, quantity: quantity, to: storageLocation?.name)
        try context.save()
        return item
    }

    public func update(_ item: InventoryItem, quantity: Decimal, unit: MeasureUnit, expiresAt: Date?, purchasedAt: Date?,
                       price: Decimal?, currency: String?, storageLocation: StorageLocation?) throws {
        let space = try editableSpace(of: item)
        try validate(quantity: quantity, expiresAt: expiresAt, purchasedAt: purchasedAt)
        try ensure(storageLocation, isIn: space)
        let previousLocation = item.storageLocation
        item.quantity = quantity
        item.unit = unit
        item.expiresAt = expiresAt
        item.purchasedAt = purchasedAt
        item.price = price
        item.currency = currency?.nilIfBlank ?? defaultCurrency
        item.storageLocation = storageLocation
        item.isFullyConsumed = false
        item.consumedAt = nil
        item.stamp(by: userRecordName, now: now())
        let relocated = previousLocation != storageLocation
        record(.edited, for: item, in: space, quantity: quantity,
               from: relocated ? previousLocation?.name : nil, to: storageLocation?.name)
        try context.save()
    }

    // MARK: Consuming

    @discardableResult
    public func consume(_ item: InventoryItem, quantity: Decimal, commit: Bool = true) throws -> ConsumptionLog {
        try applyConsume(item, quantity: quantity, commit: commit).log
    }

    @discardableResult
    public func markUsedUp(_ item: InventoryItem, commit: Bool = true) throws -> ConsumptionLog {
        _ = try editableSpace(of: item)
        return try consume(item, quantity: item.quantity, commit: commit)
    }

    /// Consume with the objects it created, so an undo can remove them again.
    func applyConsume(_ item: InventoryItem, quantity: Decimal,
                      commit: Bool) throws -> (log: ConsumptionLog, event: InventoryEvent) {
        let space = try editableSpace(of: item)
        guard quantity > 0 else { throw ServiceError.quantityMustBePositive }
        guard !item.isFullyConsumed, quantity <= item.quantity else { throw ServiceError.quantityExceedsStock }

        let date = now()
        item.quantity -= quantity
        if item.quantity == 0 {
            item.isFullyConsumed = true
            item.consumedAt = date
        }
        item.stamp(by: userRecordName, now: date)

        let log = spaceStore.insert(ConsumptionLog.self, in: space, by: userRecordName)
        log.inventoryItem = item
        log.quantity = quantity
        log.remaining = item.quantity
        log.consumedAt = date
        let event = record(.consumed, for: item, in: space, quantity: quantity, from: item.storageLocation?.name)
        if commit { try context.save() }
        return (log, event)
    }

    // MARK: Moving and deleting

    /// Moves the whole item.
    public func move(_ item: InventoryItem, to location: StorageLocation?, commit: Bool = true) throws {
        _ = try applyMove(item, quantity: nil, to: location, commit: commit)
    }

    /// Moves `quantity` of the item. Less than all of it splits the item: the moved amount becomes a
    /// new item at `location` with the same dates and price. Returns the item that is now at `location`.
    @discardableResult
    public func move(_ item: InventoryItem, quantity: Decimal, to location: StorageLocation?,
                     commit: Bool = true) throws -> InventoryItem {
        try applyMove(item, quantity: quantity, to: location, commit: commit).moved
    }

    /// Move with the objects it created. `split` is the new item of a partial move; `event` is nil for a no-op.
    func applyMove(_ item: InventoryItem, quantity: Decimal?, to location: StorageLocation?,
                   commit: Bool) throws -> (moved: InventoryItem, event: InventoryEvent?, split: InventoryItem?) {
        let space = try editableSpace(of: item)
        if let quantity {
            guard quantity > 0 else { throw ServiceError.quantityMustBePositive }
            guard !item.isFullyConsumed, quantity <= item.quantity else { throw ServiceError.quantityExceedsStock }
        }
        try ensure(location, isIn: space)
        guard item.storageLocation != location else { return (item, nil, nil) }

        let date = now()
        let from = item.storageLocation?.name
        guard let quantity, quantity < item.quantity else {
            item.storageLocation = location
            item.stamp(by: userRecordName, now: date)
            let event = record(.moved, for: item, in: space, quantity: item.quantity, from: from, to: location?.name)
            if commit { try context.save() }
            return (item, event, nil)
        }

        let split = spaceStore.insert(InventoryItem.self, in: space, by: userRecordName)
        split.product = item.product
        split.quantity = quantity
        split.unit = item.unit
        split.expiresAt = item.expiresAt
        split.purchasedAt = item.purchasedAt
        split.price = item.price
        split.currency = item.currency
        split.isFullyConsumed = false
        split.storageLocation = location
        split.shoppingLocation = item.shoppingLocation
        item.quantity -= quantity
        item.stamp(by: userRecordName, now: date)
        let event = record(.moved, for: split, in: space, quantity: quantity, from: from, to: location?.name)
        if commit { try context.save() }
        return (split, event, split)
    }

    /// Deletes the item and its logs. Its events stay with the product, plus a `deleted` one.
    public func delete(_ item: InventoryItem) throws {
        let space = try editableSpace(of: item)
        record(.deleted, for: item, in: space, quantity: item.quantity, from: item.storageLocation?.name)
        try logs(for: item).forEach(context.delete)
        context.delete(item)
        try context.save()
    }

    /// Copy then delete (spec §3.3). Returns the new item in `target`, which records an `added` event there.
    @discardableResult
    public func transfer(_ item: InventoryItem, to target: Space) throws -> InventoryItem {
        let source = try editableSpace(of: item)
        guard !target.isGone else { throw ServiceError.notFound }
        guard source != target else { return item }
        try ensureEditable(target)
        guard let product = item.product else { throw ServiceError.notFound }

        let targetProduct = try matchingProduct(for: product, in: target) ?? copy(product, to: target)
        let copyItem = spaceStore.insert(InventoryItem.self, in: target, by: userRecordName)
        copyItem.product = targetProduct
        copyItem.quantity = item.quantity
        copyItem.unit = item.unit
        copyItem.expiresAt = item.expiresAt
        copyItem.purchasedAt = item.purchasedAt
        copyItem.price = item.price
        copyItem.currency = item.currency
        copyItem.isFullyConsumed = item.isFullyConsumed
        copyItem.consumedAt = item.consumedAt
        copyItem.storageLocation = try item.storageLocation.flatMap { try storageLocation(named: $0.name, in: target) }
        copyItem.shoppingLocation = try item.shoppingLocation.flatMap { try shoppingLocation(matching: $0, in: target) }

        let sourceLogs = try logs(for: item)
        for log in sourceLogs {
            let copyLog = spaceStore.insert(ConsumptionLog.self, in: target, by: userRecordName)
            copyLog.inventoryItem = copyItem
            copyLog.quantity = log.quantity
            copyLog.remaining = log.remaining
            copyLog.consumedAt = log.consumedAt
        }
        record(.added, for: copyItem, in: target, quantity: copyItem.quantity, to: copyItem.storageLocation?.name)
        sourceLogs.forEach(context.delete)
        context.delete(item)
        try context.save()
        return copyItem
    }

    // MARK: Reading

    public func item(publicId: UUID) throws -> InventoryItem? {
        try context.fetchEntities(InventoryItem.self, where: NSPredicate(format: "publicId == %@", publicId as CVarArg)).first
    }

    public func items(in space: Space, includeConsumed: Bool = false) throws -> [InventoryItem] {
        let base = NSPredicate(format: "product.space == %@", space)
        return try context.fetchEntities(InventoryItem.self, where: includeConsumed ? base : Self.open(base))
    }

    public func items(for product: Product, includeConsumed: Bool = false) throws -> [InventoryItem] {
        let base = NSPredicate(format: "product == %@", product)
        return try context.fetchEntities(InventoryItem.self, where: includeConsumed ? base : Self.open(base),
                                         sortedBy: [NSSortDescriptor(key: "expiresAt", ascending: true)])
    }

    public func logs(for product: Product) throws -> [ConsumptionLog] {
        try context.fetchEntities(ConsumptionLog.self, where: NSPredicate(format: "inventoryItem.product == %@", product),
                                  sortedBy: [NSSortDescriptor(key: "consumedAt", ascending: false)])
    }

    public func logs(for item: InventoryItem) throws -> [ConsumptionLog] {
        try context.fetchEntities(ConsumptionLog.self, where: NSPredicate(format: "inventoryItem == %@", item),
                                  sortedBy: [NSSortDescriptor(key: "consumedAt", ascending: false)])
    }

    /// The product's stock history, newest first.
    public func events(for product: Product) throws -> [InventoryEvent] {
        try context.fetchEntities(InventoryEvent.self, where: NSPredicate(format: "product == %@", product),
                                  sortedBy: [NSSortDescriptor(key: "occurredAt", ascending: false),
                                             NSSortDescriptor(key: "createdAt", ascending: false)])
    }

    public func saveIfNeeded() throws {
        if context.hasChanges { try context.save() }
    }

    /// Removes an object an undone action created (a log, an event, the split half of a move).
    func discard(_ object: NSManagedObject) {
        guard !object.isGone else { return }
        context.delete(object)
    }

    // MARK: Helpers

    @discardableResult
    private func record(_ kind: InventoryEventKind, for item: InventoryItem, in space: Space, quantity: Decimal,
                        from: String? = nil, to: String? = nil) -> InventoryEvent {
        let event = spaceStore.insert(InventoryEvent.self, in: space, by: userRecordName)
        event.kind = kind
        event.quantity = quantity
        event.unit = item.unit
        event.fromLocationName = from
        event.toLocationName = to
        event.occurredAt = now()
        event.product = item.product
        event.inventoryItem = item
        return event
    }

    private static func open(_ predicate: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, NSPredicate(format: "isFullyConsumed == NO")])
    }

    private func editableSpace(of item: InventoryItem) throws -> Space {
        guard !item.isGone, let space = item.product?.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        return space
    }

    private func ensureEditable(_ space: Space) throws {
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
    }

    /// A location passed in must live in the item's space (CloudKit relationships cannot cross zones).
    private func ensure(_ location: StorageLocation?, isIn space: Space) throws {
        guard let location else { return }
        guard !location.isGone, location.space == space else { throw ServiceError.notFound }
    }

    private func ensure(_ location: ShoppingLocation?, isIn space: Space) throws {
        guard let location else { return }
        guard !location.isGone, location.space == space else { throw ServiceError.notFound }
    }

    private func validate(quantity: Decimal, expiresAt: Date?, purchasedAt: Date?) throws {
        guard quantity > 0 else { throw ServiceError.quantityMustBePositive }
        if let expiresAt, let purchasedAt,
           calendar.startOfDay(for: expiresAt) < calendar.startOfDay(for: purchasedAt) {
            throw ServiceError.expiryBeforePurchase
        }
    }

    private func matchingProduct(for product: Product, in target: Space) throws -> Product? {
        if let barcode = product.barcode?.nilIfBlank {
            let byBarcode = try context.fetchEntities(
                Product.self, where: NSPredicate(format: "space == %@ AND barcode == %@", target, barcode),
                sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
            if let match = byBarcode.first { return match }
        }
        return try context.fetchEntities(
            Product.self, where: NSPredicate(format: "space == %@ AND name ==[c] %@", target, product.name),
            sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)]).first
    }

    private func copy(_ product: Product, to target: Space) -> Product {
        let copy = spaceStore.insert(Product.self, in: target, by: userRecordName)
        copy.space = target
        copy.name = product.name
        copy.brand = product.brand
        copy.category = product.category
        copy.barcode = product.barcode
        copy.defaultUnit = product.defaultUnit
        copy.url = product.url
        copy.isFavorite = product.isFavorite
        copy.notes = product.notes
        copy.image = product.image
        return copy
    }

    private func storageLocation(named name: String, in space: Space) throws -> StorageLocation? {
        try context.fetchEntities(StorageLocation.self, where: NSPredicate(format: "space == %@ AND name ==[c] %@", space, name)).first
    }

    private func shoppingLocation(matching location: ShoppingLocation, in space: Space) throws -> ShoppingLocation? {
        guard let identifier = location.mapItemIdentifier?.nilIfBlank else { return nil }
        return try context.fetchEntities(
            ShoppingLocation.self, where: NSPredicate(format: "space == %@ AND mapItemIdentifier == %@", space, identifier)).first
    }
}
