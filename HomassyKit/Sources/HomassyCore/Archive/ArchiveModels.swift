import Foundation

/// The collections inside `data.json`, in dependency order: a collection only references
/// collections listed before it. Import applies them in this order.
public enum ArchiveEntity: String, CaseIterable, Codable, Sendable {
    case members, products, storageLocations, shoppingLocations, shoppingLists,
         inventoryItems, consumptionLogs, inventoryEvents, purchaseRecords, shoppingListItems
}

// SpaceKind, MeasureUnit and InventoryEventKind are Codable in Model/Enums.swift.

/// A decimal that travels as a JSON string ("0.1"), so no value ever passes through Double.
public struct DecimalString: Codable, Hashable, Sendable, CustomStringConvertible {
    public var value: Decimal

    public init(_ value: Decimal) { self.value = value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self.parse(text) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Invalid decimal string \"\(text)\"")
        }
        self.value = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String { value.description }

    static func parse(_ text: String) -> Decimal? {
        guard text.wholeMatch(of: #/-?[0-9]+(\.[0-9]+)?/#) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// ISO-8601 with milliseconds and a numeric offset: "2026-09-20T17:40:00.000+02:00".
public enum ArchiveDate {
    public static func format(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(style(timeZone: timeZone, separator: .colon, fractional: true))
    }

    public static func parse(_ text: String) -> Date? {
        for separator in [Date.ISO8601FormatStyle.TimeZoneSeparator.colon, .omitted] {
            for fractional in [true, false] {
                if let date = try? style(timeZone: .gmt, separator: separator, fractional: fractional).parse(text) {
                    return date
                }
            }
        }
        return nil
    }

    /// Millisecond resolution used for "newer updatedAt wins" comparisons, matching what the
    /// archive can represent.
    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func style(timeZone: TimeZone,
                              separator: Date.ISO8601FormatStyle.TimeZoneSeparator,
                              fractional: Bool) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .standard,
                                timeSeparator: .colon, timeZoneSeparator: separator,
                                includingFractionalSeconds: fractional, timeZone: timeZone)
    }
}

public protocol ArchiveRecord: Codable, Equatable, Sendable {
    var publicId: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var createdBy: String { get set }
    var updatedBy: String { get set }
}

public struct SpaceDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var name: String
    public var kind: SpaceKind
    public var sortOrder: Int
}

public struct MemberDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var userRecordName: String
    public var displayName: String
    public var colorSeed: String
    public var avatar: String?
}

public struct ProductDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var name: String
    public var brand: String?
    public var category: String?
    public var barcode: String?
    public var defaultUnit: MeasureUnit
    public var isFavorite: Bool
    public var notes: String?
    public var image: String?
    public var url: String?
}

public struct StorageLocationDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var name: String
    public var color: String?
    public var sortOrder: Int
    public var isFreezer: Bool
}

public struct ShoppingLocationDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var mapItemIdentifier: String?
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var lastUsedAt: Date?
}

public struct ShoppingListDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var name: String
    public var color: String?
    public var sortOrder: Int
}

public struct InventoryItemDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var product: UUID
    public var quantity: DecimalString
    public var unit: MeasureUnit
    public var expiresAt: Date?
    public var purchasedAt: Date?
    public var price: DecimalString?
    public var currency: String?
    public var isFullyConsumed: Bool
    public var consumedAt: Date?
    public var storageLocation: UUID?
    public var shoppingLocation: UUID?
}

public struct ConsumptionLogDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var inventoryItem: UUID
    public var quantity: DecimalString
    public var remaining: DecimalString
    public var consumedAt: Date?
}

/// One stock history entry. `inventoryItem` is absent once the stock item was deleted;
/// the event still belongs to its product.
public struct InventoryEventDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var product: UUID
    public var inventoryItem: UUID?
    public var kind: InventoryEventKind
    public var quantity: DecimalString
    public var unit: MeasureUnit
    public var fromLocationName: String?
    public var toLocationName: String?
    public var occurredAt: Date?
}

/// One purchase for the price trend (P4-05). `price` is the amount paid for `quantity`. The store and the
/// stock item are absent once they were deleted; the record still belongs to its product.
public struct PurchaseRecordDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var product: UUID
    public var shoppingLocation: UUID?
    public var inventoryItem: UUID?
    public var quantity: DecimalString
    public var unit: MeasureUnit
    public var price: DecimalString?
    public var currency: String?
    public var purchasedAt: Date?
}

public struct ShoppingListItemDTO: ArchiveRecord {
    public var publicId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var createdBy: String
    public var updatedBy: String
    public var list: UUID
    public var product: UUID?
    public var customName: String?
    public var quantity: DecimalString
    public var unit: MeasureUnit
    public var note: String?
    public var deadline: Date?
    public var isPurchased: Bool
    public var purchasedAt: Date?
    public var sortOrder: Int
    public var shoppingLocation: UUID?
}

public struct ArchiveCounts: Codable, Equatable, Sendable {
    public var members = 0
    public var products = 0
    public var storageLocations = 0
    public var shoppingLocations = 0
    public var shoppingLists = 0
    public var inventoryItems = 0
    public var consumptionLogs = 0
    public var inventoryEvents = 0
    public var purchaseRecords = 0
    public var shoppingListItems = 0
    public var images = 0

    public init() {}

    public subscript(entity: ArchiveEntity) -> Int {
        get {
            switch entity {
            case .members: members
            case .products: products
            case .storageLocations: storageLocations
            case .shoppingLocations: shoppingLocations
            case .shoppingLists: shoppingLists
            case .inventoryItems: inventoryItems
            case .consumptionLogs: consumptionLogs
            case .inventoryEvents: inventoryEvents
            case .purchaseRecords: purchaseRecords
            case .shoppingListItems: shoppingListItems
            }
        }
        set {
            switch entity {
            case .members: members = newValue
            case .products: products = newValue
            case .storageLocations: storageLocations = newValue
            case .shoppingLocations: shoppingLocations = newValue
            case .shoppingLists: shoppingLists = newValue
            case .inventoryItems: inventoryItems = newValue
            case .consumptionLogs: consumptionLogs = newValue
            case .inventoryEvents: inventoryEvents = newValue
            case .purchaseRecords: purchaseRecords = newValue
            case .shoppingListItems: shoppingListItems = newValue
            }
        }
    }
}

public struct ArchiveData: Codable, Equatable, Sendable {
    public var space: SpaceDTO
    public var members: [MemberDTO]
    public var products: [ProductDTO]
    public var storageLocations: [StorageLocationDTO]
    public var shoppingLocations: [ShoppingLocationDTO]
    public var shoppingLists: [ShoppingListDTO]
    public var inventoryItems: [InventoryItemDTO]
    public var consumptionLogs: [ConsumptionLogDTO]
    public var inventoryEvents: [InventoryEventDTO]
    public var shoppingListItems: [ShoppingListItemDTO]
    /// Added in P4-05; absent from older files, which still decode (see the `Decodable` extension).
    public var purchaseRecords: [PurchaseRecordDTO] = []

    /// Distinct image paths referenced by products and member avatars.
    public var imageReferences: Set<String> {
        Set(products.compactMap(\.image) + members.compactMap(\.avatar))
    }

    public var counts: ArchiveCounts {
        var counts = ArchiveCounts()
        counts.members = members.count
        counts.products = products.count
        counts.storageLocations = storageLocations.count
        counts.shoppingLocations = shoppingLocations.count
        counts.shoppingLists = shoppingLists.count
        counts.inventoryItems = inventoryItems.count
        counts.consumptionLogs = consumptionLogs.count
        counts.inventoryEvents = inventoryEvents.count
        counts.purchaseRecords = purchaseRecords.count
        counts.shoppingListItems = shoppingListItems.count
        counts.images = imageReferences.count
        return counts
    }
}

// Collections added after schema version 1 decode as empty when absent, so older files still open, and are
// left out while empty, so an archive without them is byte-for-byte what version 1 wrote.
extension ArchiveCounts {
    enum CodingKeys: String, CodingKey {
        case members, products, storageLocations, shoppingLocations, shoppingLists, inventoryItems,
             consumptionLogs, inventoryEvents, purchaseRecords, shoppingListItems, images
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(members, forKey: .members)
        try container.encode(products, forKey: .products)
        try container.encode(storageLocations, forKey: .storageLocations)
        try container.encode(shoppingLocations, forKey: .shoppingLocations)
        try container.encode(shoppingLists, forKey: .shoppingLists)
        try container.encode(inventoryItems, forKey: .inventoryItems)
        try container.encode(consumptionLogs, forKey: .consumptionLogs)
        try container.encode(inventoryEvents, forKey: .inventoryEvents)
        if purchaseRecords > 0 { try container.encode(purchaseRecords, forKey: .purchaseRecords) }
        try container.encode(shoppingListItems, forKey: .shoppingListItems)
        try container.encode(images, forKey: .images)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        members = try container.decode(Int.self, forKey: .members)
        products = try container.decode(Int.self, forKey: .products)
        storageLocations = try container.decode(Int.self, forKey: .storageLocations)
        shoppingLocations = try container.decode(Int.self, forKey: .shoppingLocations)
        shoppingLists = try container.decode(Int.self, forKey: .shoppingLists)
        inventoryItems = try container.decode(Int.self, forKey: .inventoryItems)
        consumptionLogs = try container.decode(Int.self, forKey: .consumptionLogs)
        inventoryEvents = try container.decode(Int.self, forKey: .inventoryEvents)
        purchaseRecords = try container.decodeIfPresent(Int.self, forKey: .purchaseRecords) ?? 0
        shoppingListItems = try container.decode(Int.self, forKey: .shoppingListItems)
        images = try container.decode(Int.self, forKey: .images)
    }
}

extension ArchiveData {
    enum CodingKeys: String, CodingKey {
        case space, members, products, storageLocations, shoppingLocations, shoppingLists, inventoryItems,
             consumptionLogs, inventoryEvents, shoppingListItems, purchaseRecords
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(space, forKey: .space)
        try container.encode(members, forKey: .members)
        try container.encode(products, forKey: .products)
        try container.encode(storageLocations, forKey: .storageLocations)
        try container.encode(shoppingLocations, forKey: .shoppingLocations)
        try container.encode(shoppingLists, forKey: .shoppingLists)
        try container.encode(inventoryItems, forKey: .inventoryItems)
        try container.encode(consumptionLogs, forKey: .consumptionLogs)
        try container.encode(inventoryEvents, forKey: .inventoryEvents)
        try container.encode(shoppingListItems, forKey: .shoppingListItems)
        if !purchaseRecords.isEmpty { try container.encode(purchaseRecords, forKey: .purchaseRecords) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(space: try container.decode(SpaceDTO.self, forKey: .space),
                  members: try container.decode([MemberDTO].self, forKey: .members),
                  products: try container.decode([ProductDTO].self, forKey: .products),
                  storageLocations: try container.decode([StorageLocationDTO].self, forKey: .storageLocations),
                  shoppingLocations: try container.decode([ShoppingLocationDTO].self, forKey: .shoppingLocations),
                  shoppingLists: try container.decode([ShoppingListDTO].self, forKey: .shoppingLists),
                  inventoryItems: try container.decode([InventoryItemDTO].self, forKey: .inventoryItems),
                  consumptionLogs: try container.decode([ConsumptionLogDTO].self, forKey: .consumptionLogs),
                  inventoryEvents: try container.decode([InventoryEventDTO].self, forKey: .inventoryEvents),
                  shoppingListItems: try container.decode([ShoppingListItemDTO].self, forKey: .shoppingListItems),
                  purchaseRecords: try container.decodeIfPresent([PurchaseRecordDTO].self,
                                                                 forKey: .purchaseRecords) ?? [])
    }
}

public struct ArchiveManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var locale: String
    public var timeZone: String
    public var spaceName: String
    public var spaceKind: SpaceKind
    public var counts: ArchiveCounts
}

public struct ArchiveContents: Equatable, Sendable {
    public var manifest: ArchiveManifest
    public var data: ArchiveData

    public init(manifest: ArchiveManifest, data: ArchiveData) {
        self.manifest = manifest
        self.data = data
    }
}

public struct ArchiveFiles: Sendable {
    public let manifest: Data
    public let data: Data
}
