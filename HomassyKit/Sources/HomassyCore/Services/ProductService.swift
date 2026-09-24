import CoreData
import Foundation

@MainActor
public final class ProductService {
    private let spaceStore: SpaceStore
    public let context: NSManagedObjectContext
    public let userRecordName: String
    private let canEditSpace: @MainActor (Space) -> Bool

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        self.canEditSpace = canEdit
    }

    public func canEdit(_ space: Space) -> Bool { canEditSpace(space) }

    // MARK: Writing

    @discardableResult
    public func create(in space: Space, draft: ProductDraft) async throws -> Product {
        guard !space.isGone else { throw ServiceError.notFound }
        try ensureEditable(space)
        let name = try validatedName(draft.name)
        let url = try Self.normalizedURL(draft.url)
        let image = try await Self.processedImage(draft.imageData)

        let product = spaceStore.insert(Product.self, in: space, by: userRecordName)
        product.space = space
        apply(draft, name: name, url: url, image: image, to: product)
        try context.save()
        return product
    }

    public func update(_ product: Product, with draft: ProductDraft) async throws {
        guard !product.isGone, let space = product.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        let name = try validatedName(draft.name)
        let url = try Self.normalizedURL(draft.url)
        let image: Data?
        if draft.imageData == product.image {
            image = product.image
        } else {
            image = try await Self.processedImage(draft.imageData)
        }
        guard !product.isGone else { throw ServiceError.notFound }

        apply(draft, name: name, url: url, image: image, to: product)
        product.stamp(by: userRecordName)
        try context.save()
    }

    /// The favourite heart in the product detail. Saves at once; no undo.
    public func setFavorite(_ product: Product, _ isFavorite: Bool) throws {
        guard !product.isGone, let space = product.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        guard product.isFavorite != isFavorite else { return }
        product.isFavorite = isFavorite
        product.stamp(by: userRecordName)
        try context.save()
    }

    public func delete(_ product: Product) throws {
        guard !product.isGone, let space = product.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        let logs = try context.fetchEntities(ConsumptionLog.self, where: NSPredicate(format: "inventoryItem.product == %@", product))
        let items = try context.fetchEntities(InventoryItem.self, where: NSPredicate(format: "product == %@", product))
        logs.forEach(context.delete)
        items.forEach(context.delete)
        context.delete(product)
        try context.save()
    }

    /// Hides the product now; deletes and saves when the undo window commits.
    /// The action holds the service strongly: callers often build a service just for this call.
    public func deletion(of product: Product, pending: PendingDeletions) throws -> UndoableAction {
        guard !product.isGone, let space = product.space else { throw ServiceError.notFound }
        try ensureEditable(space)
        return pending.deletion(of: product.publicId, title: UndoTitle.removed(product.name)) {
            guard !product.isGone else { return }
            try self.delete(product)
        }
    }

    // MARK: Reading

    public func products(in space: Space) throws -> [Product] {
        sortedByName(try context.fetchEntities(Product.self, where: NSPredicate(format: "space == %@", space)), name: \.name)
    }

    public func product(publicId: UUID) throws -> Product? {
        try context.fetchEntities(Product.self, where: NSPredicate(format: "publicId == %@", publicId as CVarArg)).first
    }

    public func product(barcode: String, in space: Space) throws -> Product? {
        guard let code = barcode.nilIfBlank else { return nil }
        let matches = try context.fetchEntities(
            Product.self, where: NSPredicate(format: "space == %@ AND barcode == %@", space, code),
            sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
        return matches.first
    }

    public func search(_ query: String, in space: Space) throws -> [Product] {
        guard let text = query.nilIfBlank else { return try products(in: space) }
        let predicate = NSPredicate(
            format: "space == %@ AND (name CONTAINS[cd] %@ OR brand CONTAINS[cd] %@ OR category CONTAINS[cd] %@ OR barcode CONTAINS %@)",
            space, text, text, text, text)
        return sortedByName(try context.fetchEntities(Product.self, where: predicate), name: \.name)
    }

    /// Distinct ignoring case; the spelling entered first wins ("Dairy" over a later "dairy").
    public func categories(in space: Space) throws -> [String] {
        let products = try context.fetchEntities(Product.self, where: NSPredicate(format: "space == %@", space),
                                                 sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
        var seen = Set<String>()
        let distinct = products.compactMap { $0.category?.nilIfBlank }.filter { seen.insert($0.lowercased()).inserted }
        return sortedByName(distinct, name: { $0 })
    }

    // MARK: Helpers

    func ensureEditable(_ space: Space) throws {
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
    }

    /// Trimmed; `https://` is added when there is no scheme. Only http(s) links with a host are accepted.
    static func normalizedURL(_ text: String) throws -> String? {
        guard let trimmed = text.nilIfBlank else { return nil }
        let candidate = trimmed.contains("://") || trimmed.lowercased().hasPrefix("mailto:") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, host.contains(".") || host == "localhost",
              components.url != nil
        else { throw ServiceError.invalidURL }
        return candidate
    }

    private func validatedName(_ name: String) throws -> String {
        guard let value = name.nilIfBlank else { throw ServiceError.nameRequired }
        return value
    }

    private func apply(_ draft: ProductDraft, name: String, url: String?, image: Data?, to product: Product) {
        product.name = name
        product.brand = draft.brand.nilIfBlank
        product.category = draft.category.nilIfBlank
        product.barcode = draft.barcode.nilIfBlank
        product.defaultUnit = draft.defaultUnit
        product.url = url
        product.isFavorite = draft.isFavorite
        product.notes = draft.notes.nilIfBlank
        product.image = image
    }

    /// Decoding a 12 MP photo takes long enough to hitch the UI, so it runs detached.
    nonisolated static func processedImage(_ data: Data?) async throws -> Data? {
        guard let data else { return nil }
        return try await Task.detached(priority: .userInitiated) { try ImageProcessor.prepare(data) }.value
    }
}
