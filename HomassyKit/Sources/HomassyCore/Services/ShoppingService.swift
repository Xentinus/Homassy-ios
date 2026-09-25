import CoreData
import Foundation

public enum BarcodeAddResult {
    case added(ShoppingListItem)
    case unknown(barcode: String)
}

/// The only code that writes shopping lists and their items (spec §3.4, §4).
@MainActor
public final class ShoppingService {
    public let context: NSManagedObjectContext
    public let userRecordName: String
    public let spaceStore: SpaceStore
    private let canEditSpace: @MainActor (Space) -> Bool
    private let now: () -> Date

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                now: @escaping () -> Date = { Date() }) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        self.canEditSpace = canEdit
        self.now = now
    }

    public func canEdit(_ space: Space) -> Bool { canEditSpace(space) }

    public static func displayName(of item: ShoppingListItem) -> String {
        if let product = item.product { return product.name }
        return item.customName ?? ""
    }

    public func save() throws {
        if context.hasChanges { try context.save() }
    }

    // MARK: Lists

    public func lists(in space: Space) throws -> [ShoppingList] {
        try context.fetchEntities(ShoppingList.self, where: NSPredicate(format: "space == %@", space)).sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    @discardableResult
    public func createList(name: String, color: String? = nil, in space: Space) throws -> ShoppingList {
        guard !space.isGone else { throw ServiceError.notFound }
        try ensureEditable(space)
        let value = try Self.requiredName(name)
        let nextOrder = (try lists(in: space).map { Int($0.sortOrder) }.max() ?? -1) + 1

        let list = spaceStore.insert(ShoppingList.self, in: space, by: userRecordName)
        list.space = space
        list.name = value
        list.color = color
        list.sortOrder = numericCast(nextOrder)
        list.stamp(by: userRecordName, now: now())
        try save()
        return list
    }

    public func updateList(_ list: ShoppingList, name: String, color: String?) throws {
        try editableSpace(of: list)
        list.name = try Self.requiredName(name)
        list.color = color
        list.stamp(by: userRecordName, now: now())
        try save()
    }

    public func renameList(_ list: ShoppingList, to name: String) throws {
        try updateList(list, name: name, color: list.color)
    }

    public func reorderLists(_ ordered: [ShoppingList]) throws {
        for list in ordered { try editableSpace(of: list) }
        let date = now()
        for (index, list) in ordered.enumerated() where Int(list.sortOrder) != index {
            list.sortOrder = numericCast(index)
            list.stamp(by: userRecordName, now: date)
        }
        try save()
    }

    /// Deletes the list; its items go with it (cascade).
    public func deleteList(_ list: ShoppingList) throws {
        try editableSpace(of: list)
        context.delete(list)
        try save()
    }

    // MARK: Items

    public func items(in list: ShoppingList) throws -> [ShoppingListItem] {
        try context.fetchEntities(ShoppingListItem.self, where: NSPredicate(format: "shoppingList == %@", list))
    }

    /// Sort order ascending; purchasing keeps an item's `sortOrder`, so un-purchasing puts it back in place.
    public func unpurchasedItems(in list: ShoppingList) throws -> [ShoppingListItem] {
        try items(in: list).filter { !$0.isPurchased }.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt < b.createdAt
        }
    }

    /// Most recently purchased first.
    public func purchasedItems(in list: ShoppingList) throws -> [ShoppingListItem] {
        try items(in: list).filter(\.isPurchased).sorted {
            ($0.purchasedAt ?? .distantPast) > ($1.purchasedAt ?? .distantPast)
        }
    }

    @discardableResult
    public func addItem(to list: ShoppingList, product: Product? = nil, customName: String? = nil,
                        quantity: Decimal = 1, unit: MeasureUnit? = nil, note: String? = nil,
                        deadline: Date? = nil, shoppingLocation: ShoppingLocation? = nil) throws -> ShoppingListItem {
        let space = try editableSpace(of: list)
        try validate(product: product, customName: customName, quantity: quantity,
                     shoppingLocation: shoppingLocation, in: space)
        let nextOrder = (try items(in: list).map { Int($0.sortOrder) }.max() ?? -1) + 1

        let item = spaceStore.insert(ShoppingListItem.self, in: space, by: userRecordName)
        item.shoppingList = list
        item.product = product
        item.customName = product == nil ? customName?.nilIfBlank : nil
        item.quantity = quantity
        item.unit = unit ?? product?.defaultUnit ?? .piece
        item.note = note?.nilIfBlank
        item.deadline = deadline
        item.isPurchased = false
        item.purchasedAt = nil
        item.shoppingLocation = shoppingLocation
        item.sortOrder = numericCast(nextOrder)
        item.stamp(by: userRecordName, now: now())
        try save()
        return item
    }

    public func updateItem(_ item: ShoppingListItem, product: Product?, customName: String?, quantity: Decimal,
                           unit: MeasureUnit, note: String?, deadline: Date?,
                           shoppingLocation: ShoppingLocation?) throws {
        let space = try editableSpace(of: item)
        try validate(product: product, customName: customName, quantity: quantity,
                     shoppingLocation: shoppingLocation, in: space)

        item.product = product
        item.customName = product == nil ? customName?.nilIfBlank : nil
        item.quantity = quantity
        item.unit = unit
        item.note = note?.nilIfBlank
        item.deadline = deadline
        item.shoppingLocation = shoppingLocation
        item.stamp(by: userRecordName, now: now())
        try save()
    }

    public func deleteItem(_ item: ShoppingListItem) throws {
        try editableSpace(of: item)
        context.delete(item)
        try save()
    }

    public func reorderItems(_ ordered: [ShoppingListItem]) throws {
        for item in ordered { try editableSpace(of: item) }
        let date = now()
        for (index, item) in ordered.enumerated() where Int(item.sortOrder) != index {
            item.sortOrder = numericCast(index)
            item.stamp(by: userRecordName, now: date)
        }
        try save()
    }

    /// Applies a purchase state without saving; `ShoppingActions` saves on commit.
    public func applyPurchased(_ item: ShoppingListItem, _ purchased: Bool) {
        let date = now()
        item.isPurchased = purchased
        item.purchasedAt = purchased ? date : nil
        item.stamp(by: userRecordName, now: date)
    }

    public func togglePurchased(_ item: ShoppingListItem) throws {
        try editableSpace(of: item)
        applyPurchased(item, !item.isPurchased)
        try save()
    }

    @discardableResult
    public func clearPurchased(in list: ShoppingList) throws -> Int {
        try editableSpace(of: list)
        let purchased = try purchasedItems(in: list)
        for item in purchased { context.delete(item) }
        try save()
        return purchased.count
    }

    // MARK: Barcode and suggestions

    /// A barcode known in the list's space adds that product, or bumps its open item by one.
    /// Anything else comes back as `.unknown` so the UI can offer the product form.
    public func addFromBarcode(_ barcode: String, to list: ShoppingList) throws -> BarcodeAddResult {
        let space = try editableSpace(of: list)
        guard let code = barcode.nilIfBlank,
              let product = try context.fetchEntities(
                Product.self, where: NSPredicate(format: "space == %@ AND barcode == %@", space, code)).first
        else { return .unknown(barcode: barcode.trimmingCharacters(in: .whitespacesAndNewlines)) }

        if let existing = try unpurchasedItems(in: list).first(where: { $0.product == product }) {
            existing.quantity += 1
            existing.stamp(by: userRecordName, now: now())
            try save()
            return .added(existing)
        }
        return .added(try addItem(to: list, product: product))
    }

    /// Name matches, ranked prefix first, then favourites, then name.
    public func productSuggestions(matching text: String, in space: Space, limit: Int = 8) throws -> [Product] {
        guard let query = text.nilIfBlank else { return [] }
        let folded = Self.fold(query)
        let matches = try context.fetchEntities(
            Product.self, where: NSPredicate(format: "space == %@ AND name CONTAINS[cd] %@", space, query))
        let ranked = matches.sorted { a, b in
            let aPrefix = Self.fold(a.name).hasPrefix(folded)
            let bPrefix = Self.fold(b.name).hasPrefix(folded)
            if aPrefix != bPrefix { return aPrefix }
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }

    // MARK: Helpers

    @discardableResult
    private func editableSpace(of list: ShoppingList) throws -> Space {
        guard !list.isGone, let space = list.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        return space
    }

    @discardableResult
    private func editableSpace(of item: ShoppingListItem) throws -> Space {
        guard !item.isGone, let list = item.shoppingList else { throw ServiceError.notFound }
        return try editableSpace(of: list)
    }

    private func ensureEditable(_ space: Space) throws {
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
    }

    private func validate(product: Product?, customName: String?, quantity: Decimal,
                          shoppingLocation: ShoppingLocation?, in space: Space) throws {
        if product == nil { _ = try Self.requiredName(customName ?? "") }
        guard quantity > 0 else { throw ServiceError.quantityMustBePositive }
        guard product.map({ !$0.isGone && $0.space == space }) ?? true,
              shoppingLocation.map({ !$0.isGone && $0.space == space }) ?? true else { throw ServiceError.notFound }
    }

    private static func requiredName(_ name: String) throws -> String {
        guard let value = name.nilIfBlank else { throw ServiceError.nameRequired }
        return value
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
