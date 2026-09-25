import CoreData
import Foundation

@MainActor
public final class ArchiveExporter {
    private let context: NSManagedObjectContext
    private let userRecordName: String?
    private let ownsSpace: @MainActor (Space) -> Bool
    private let appVersion: String
    private let locale: Locale
    private let timeZone: TimeZone
    private let now: () -> Date

    /// `ownsSpace` decides whose photos travel: the owner exports everyone's, anyone else only their own
    /// (`userRecordName`). Names and colours always stay, so attribution keeps working.
    public init(context: NSManagedObjectContext,
                userRecordName: String? = nil,
                ownsSpace: @escaping @MainActor (Space) -> Bool = { _ in true },
                appVersion: String = ArchiveExporter.bundleVersion(),
                locale: Locale = .current,
                timeZone: TimeZone = .current,
                now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.userRecordName = userRecordName
        self.ownsSpace = ownsSpace
        self.appVersion = appVersion
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
    }

    nonisolated public static func bundleVersion() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    nonisolated public static func fileName(spaceName: String, date: Date, timeZone: TimeZone) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = spaceName.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "Homassy" : cleaned
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        return "\(base)-\(day).\(ArchivePackage.fileExtension)"
    }

    /// Writes the archive into a fresh temporary directory and returns its URL. The caller hands it
    /// to `.fileExporter`; the system cleans the temporary directory.
    public func export(space: Space) throws -> URL {
        let loaded = try snapshot(of: space)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "HomassyExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.fileName(spaceName: space.name,
                                                       date: loaded.contents.manifest.exportedAt,
                                                       timeZone: timeZone))
        try ArchivePackage.write(loaded.contents, images: loaded.images, to: url)
        return url
    }

    /// Everything the archive will contain, including unsaved changes in `context`.
    public func snapshot(of space: Space) throws -> ArchivePackage.Loaded {
        var images: [String: Data] = [:]
        func imageReference(_ data: Data?) -> String? {
            guard let data, !data.isEmpty else { return nil }
            let reference = ArchiveImages.reference(for: data)
            images[reference] = data
            return reference
        }
        func nonEmpty(_ text: String?) -> String? {
            guard let text, !text.isEmpty else { return nil }
            return text
        }

        let isOwner = ownsSpace(space)
        var members: [MemberDTO] = []
        for m in try fetch(Member.self, "space == %@", space) {
            let keepsPhoto = isOwner || (m.userRecordName != nil && m.userRecordName == userRecordName)
            members.append(MemberDTO(publicId: m.publicId, createdAt: m.createdAt, updatedAt: m.updatedAt,
                                     createdBy: m.createdBy, updatedBy: m.updatedBy,
                                     userRecordName: m.userRecordName ?? "", displayName: m.displayName ?? "",
                                     colorSeed: m.colorSeed ?? m.userRecordName ?? "",
                                     avatar: keepsPhoto ? imageReference(m.avatar) : nil, colorKey: m.colorKey))
        }

        var products: [ProductDTO] = []
        for p in try fetch(Product.self, "space == %@", space) {
            products.append(ProductDTO(publicId: p.publicId, createdAt: p.createdAt, updatedAt: p.updatedAt,
                                       createdBy: p.createdBy, updatedBy: p.updatedBy,
                                       name: p.name, brand: nonEmpty(p.brand), category: nonEmpty(p.category),
                                       barcode: nonEmpty(p.barcode), defaultUnit: p.defaultUnit,
                                       isFavorite: p.isFavorite, notes: nonEmpty(p.notes),
                                       image: imageReference(p.image), url: nonEmpty(p.url)))
        }

        let storageLocations = try fetch(StorageLocation.self, "space == %@", space).map { s in
            StorageLocationDTO(publicId: s.publicId, createdAt: s.createdAt, updatedAt: s.updatedAt,
                               createdBy: s.createdBy, updatedBy: s.updatedBy, name: s.name,
                               color: nonEmpty(s.color), sortOrder: numericCast(s.sortOrder),
                               isFreezer: s.isFreezer)
        }

        let shoppingLocations = try fetch(ShoppingLocation.self, "space == %@", space).map { l in
            ShoppingLocationDTO(publicId: l.publicId, createdAt: l.createdAt, updatedAt: l.updatedAt,
                                createdBy: l.createdBy, updatedBy: l.updatedBy,
                                mapItemIdentifier: nonEmpty(l.mapItemIdentifier), name: l.name,
                                latitude: l.latitude, longitude: l.longitude, lastUsedAt: l.lastUsedAt)
        }

        let shoppingLists = try fetch(ShoppingList.self, "space == %@", space).map { l in
            ShoppingListDTO(publicId: l.publicId, createdAt: l.createdAt, updatedAt: l.updatedAt,
                            createdBy: l.createdBy, updatedBy: l.updatedBy, name: l.name,
                            color: nonEmpty(l.color), sortOrder: numericCast(l.sortOrder))
        }

        let inventoryItems = try fetch(InventoryItem.self, "product.space == %@", space).compactMap { i -> InventoryItemDTO? in
            guard let product = i.product else { return nil }
            return InventoryItemDTO(publicId: i.publicId, createdAt: i.createdAt, updatedAt: i.updatedAt,
                                    createdBy: i.createdBy, updatedBy: i.updatedBy,
                                    product: product.publicId, quantity: DecimalString(i.quantity),
                                    unit: i.unit, expiresAt: i.expiresAt, purchasedAt: i.purchasedAt,
                                    price: i.price.map(DecimalString.init), currency: nonEmpty(i.currency),
                                    isFullyConsumed: i.isFullyConsumed, consumedAt: i.consumedAt,
                                    storageLocation: i.storageLocation?.publicId,
                                    shoppingLocation: i.shoppingLocation?.publicId)
        }

        let consumptionLogs = try fetch(ConsumptionLog.self, "inventoryItem.product.space == %@", space)
            .compactMap { c -> ConsumptionLogDTO? in
                guard let item = c.inventoryItem else { return nil }
                return ConsumptionLogDTO(publicId: c.publicId, createdAt: c.createdAt, updatedAt: c.updatedAt,
                                         createdBy: c.createdBy, updatedBy: c.updatedBy,
                                         inventoryItem: item.publicId, quantity: DecimalString(c.quantity),
                                         remaining: DecimalString(c.remaining), consumedAt: c.consumedAt)
            }

        // A deleted stock item leaves its events behind; they keep the product but lose the item.
        let inventoryEvents = try fetch(InventoryEvent.self, "product.space == %@", space)
            .compactMap { e -> InventoryEventDTO? in
                guard let product = e.product else { return nil }
                return InventoryEventDTO(publicId: e.publicId, createdAt: e.createdAt, updatedAt: e.updatedAt,
                                         createdBy: e.createdBy, updatedBy: e.updatedBy,
                                         product: product.publicId, inventoryItem: e.inventoryItem?.publicId,
                                         kind: e.kind, quantity: DecimalString(e.quantity), unit: e.unit,
                                         fromLocationName: nonEmpty(e.fromLocationName),
                                         toLocationName: nonEmpty(e.toLocationName), occurredAt: e.occurredAt)
            }

        // Purchases stay with their product when the store or the stock item is gone (P4-05).
        let purchaseRecords = try fetch(PurchaseRecord.self, "product.space == %@", space)
            .compactMap { r -> PurchaseRecordDTO? in
                guard let product = r.product else { return nil }
                return PurchaseRecordDTO(publicId: r.publicId, createdAt: r.createdAt, updatedAt: r.updatedAt,
                                         createdBy: r.createdBy, updatedBy: r.updatedBy, product: product.publicId,
                                         shoppingLocation: r.shoppingLocation?.publicId,
                                         inventoryItem: r.inventoryItem?.publicId,
                                         quantity: DecimalString(r.quantity), unit: r.unit,
                                         price: r.price.map(DecimalString.init), currency: nonEmpty(r.currency),
                                         purchasedAt: r.purchasedAt)
            }

        let shoppingListItems = try fetch(ShoppingListItem.self, "shoppingList.space == %@", space)
            .compactMap { i -> ShoppingListItemDTO? in
                guard let list = i.shoppingList else { return nil }
                return ShoppingListItemDTO(publicId: i.publicId, createdAt: i.createdAt, updatedAt: i.updatedAt,
                                           createdBy: i.createdBy, updatedBy: i.updatedBy,
                                           list: list.publicId, product: i.product?.publicId,
                                           customName: nonEmpty(i.customName), quantity: DecimalString(i.quantity),
                                           unit: i.unit, note: nonEmpty(i.note), deadline: i.deadline,
                                           isPurchased: i.isPurchased, purchasedAt: i.purchasedAt,
                                           sortOrder: numericCast(i.sortOrder),
                                           shoppingLocation: i.shoppingLocation?.publicId)
            }

        let data = ArchiveData(
            space: SpaceDTO(publicId: space.publicId, createdAt: space.createdAt, updatedAt: space.updatedAt,
                            createdBy: space.createdBy, updatedBy: space.updatedBy, name: space.name,
                            kind: space.kind, sortOrder: numericCast(space.sortOrder)),
            members: members, products: products, storageLocations: storageLocations,
            shoppingLocations: shoppingLocations, shoppingLists: shoppingLists,
            inventoryItems: inventoryItems, consumptionLogs: consumptionLogs,
            inventoryEvents: inventoryEvents, shoppingListItems: shoppingListItems, purchaseRecords: purchaseRecords)
        let manifest = ArchiveManifest(schemaVersion: ArchiveCodec.supportedSchemaVersion, exportedAt: now(),
                                       appVersion: appVersion, locale: locale.identifier(.bcp47),
                                       timeZone: timeZone.identifier, spaceName: space.name,
                                       spaceKind: space.kind, counts: data.counts)
        return ArchivePackage.Loaded(contents: ArchiveContents(manifest: manifest, data: data), images: images)
    }

    private func fetch<T: HomassyEntity>(_ type: T.Type, _ format: String, _ space: Space) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: format, space)
        return try context.fetch(request).sorted { $0.publicId.uuidString < $1.publicId.uuidString }
    }
}
