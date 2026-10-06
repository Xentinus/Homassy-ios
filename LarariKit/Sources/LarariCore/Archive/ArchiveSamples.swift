#if DEBUG
import Foundation

/// The contents of `Tests/LarariCoreTests/Fixtures/sample-v1`, as values. Debug builds only.
public enum ArchiveSamples {
    public static let spaceID = id("10000000-0000-4000-8000-000000000001")
    public static let ownerMemberID = id("20000000-0000-4000-8000-000000000001")
    public static let annaMemberID = id("20000000-0000-4000-8000-000000000002")
    public static let milkID = id("30000000-0000-4000-8000-000000000001")
    public static let flourID = id("30000000-0000-4000-8000-000000000002")
    public static let fridgeID = id("40000000-0000-4000-8000-000000000001")
    public static let sparID = id("50000000-0000-4000-8000-000000000001")
    public static let milkItemID = id("60000000-0000-4000-8000-000000000001")
    public static let flourItemID = id("60000000-0000-4000-8000-000000000002")
    public static let milkLogID = id("70000000-0000-4000-8000-000000000001")
    public static let weeklyListID = id("80000000-0000-4000-8000-000000000001")
    public static let milkListItemID = id("90000000-0000-4000-8000-000000000001")
    public static let breadListItemID = id("90000000-0000-4000-8000-000000000002")
    public static let milkAddedEventID = id("A0000000-0000-4000-8000-000000000001")
    public static let milkConsumedEventID = id("A0000000-0000-4000-8000-000000000002")
    public static let flourAddedEventID = id("A0000000-0000-4000-8000-000000000003")
    /// The event of a milk stock item that was deleted: it has no stock item reference.
    public static let milkDeletedEventID = id("A0000000-0000-4000-8000-000000000004")

    /// Every publicId in the sample.
    public static var allIDs: Set<UUID> {
        [spaceID, ownerMemberID, annaMemberID, milkID, flourID, fridgeID, sparID, milkItemID,
         flourItemID, milkLogID, weeklyListID, milkListItemID, breadListItemID,
         milkAddedEventID, milkConsumedEventID, flourAddedEventID, milkDeletedEventID]
    }

    public static let sampleV1: ArchiveContents = {
        let owner = "_owner0001"
        let anna = "_member0002"
        let data = ArchiveData(
            space: SpaceDTO(publicId: spaceID,
                            createdAt: date("2026-01-10T09:00:00.000+01:00"),
                            updatedAt: date("2026-09-20T18:30:00.000+02:00"),
                            createdBy: owner, updatedBy: owner,
                            name: "Otthon", kind: .household, sortOrder: 1),
            members: [
                MemberDTO(publicId: ownerMemberID,
                          createdAt: date("2026-01-10T09:00:00.000+01:00"),
                          updatedAt: date("2026-01-10T09:00:00.000+01:00"),
                          createdBy: owner, updatedBy: owner,
                          userRecordName: owner, displayName: "Béla", colorSeed: owner, avatar: nil),
                MemberDTO(publicId: annaMemberID,
                          createdAt: date("2026-02-01T12:00:00.000+01:00"),
                          updatedAt: date("2026-02-01T12:00:00.000+01:00"),
                          createdBy: anna, updatedBy: anna,
                          userRecordName: anna, displayName: "Anna", colorSeed: anna, avatar: nil),
            ],
            products: [
                ProductDTO(publicId: milkID,
                           createdAt: date("2026-01-12T10:00:00.000+01:00"),
                           updatedAt: date("2026-09-01T08:15:00.000+02:00"),
                           createdBy: owner, updatedBy: anna,
                           name: "Tej", brand: "Mizo", category: "Tejtermék", barcode: "5998200110039",
                           defaultUnit: .liter, isFavorite: true, notes: nil, image: nil,
                           url: "https://www.mizo.hu/termekek/tej"),
                ProductDTO(publicId: flourID,
                           createdAt: date("2026-01-12T10:05:00.000+01:00"),
                           updatedAt: date("2026-01-12T10:05:00.000+01:00"),
                           createdBy: owner, updatedBy: owner,
                           name: "Liszt", brand: nil, category: "Alapanyag", barcode: nil,
                           defaultUnit: .kilogram, isFavorite: false, notes: "BL55", image: nil, url: nil),
            ],
            storageLocations: [
                StorageLocationDTO(publicId: fridgeID,
                                   createdAt: date("2026-01-10T09:05:00.000+01:00"),
                                   updatedAt: date("2026-01-10T09:05:00.000+01:00"),
                                   createdBy: owner, updatedBy: owner,
                                   name: "Hűtő", color: "#4A90D9", sortOrder: 0, isFreezer: false),
            ],
            shoppingLocations: [
                ShoppingLocationDTO(publicId: sparID,
                                    createdAt: date("2026-03-05T10:55:00.000+01:00"),
                                    updatedAt: date("2026-09-20T17:45:00.000+02:00"),
                                    createdBy: owner, updatedBy: owner,
                                    mapItemIdentifier: "I6FD7682FD36BB3BE", name: "Spar Market",
                                    latitude: 47.4979, longitude: 19.0402,
                                    lastUsedAt: date("2026-09-20T17:45:00.000+02:00")),
            ],
            shoppingLists: [
                ShoppingListDTO(publicId: weeklyListID,
                                createdAt: date("2026-01-15T08:00:00.000+01:00"),
                                updatedAt: date("2026-09-20T17:42:00.000+02:00"),
                                createdBy: owner, updatedBy: anna,
                                name: "Heti bevásárlás", color: "#E0A458", sortOrder: 0),
            ],
            inventoryItems: [
                InventoryItemDTO(publicId: milkItemID,
                                 createdAt: date("2026-09-20T17:50:00.000+02:00"),
                                 updatedAt: date("2026-09-21T07:30:00.000+02:00"),
                                 createdBy: owner, updatedBy: anna,
                                 product: milkID, quantity: decimal("1.5"), unit: .liter,
                                 expiresAt: date("2026-09-28T00:00:00.000+02:00"),
                                 purchasedAt: date("2026-09-20T17:40:00.000+02:00"),
                                 price: decimal("459"), currency: "HUF",
                                 isFullyConsumed: false, consumedAt: nil,
                                 storageLocation: fridgeID, shoppingLocation: sparID),
                InventoryItemDTO(publicId: flourItemID,
                                 createdAt: date("2026-03-05T11:05:00.000+01:00"),
                                 updatedAt: date("2026-03-05T11:05:00.000+01:00"),
                                 createdBy: owner, updatedBy: owner,
                                 product: flourID, quantity: decimal("0.1"), unit: .kilogram,
                                 expiresAt: nil,
                                 purchasedAt: date("2026-03-05T11:00:00.000+01:00"),
                                 price: decimal("1.99"), currency: "EUR",
                                 isFullyConsumed: false, consumedAt: nil,
                                 storageLocation: nil, shoppingLocation: nil),
            ],
            consumptionLogs: [
                ConsumptionLogDTO(publicId: milkLogID,
                                  createdAt: date("2026-09-21T07:30:00.000+02:00"),
                                  updatedAt: date("2026-09-21T07:30:00.000+02:00"),
                                  createdBy: anna, updatedBy: anna,
                                  inventoryItem: milkItemID, quantity: decimal("0.5"),
                                  remaining: decimal("1.5"),
                                  consumedAt: date("2026-09-21T07:30:00.000+02:00")),
            ],
            inventoryEvents: [
                InventoryEventDTO(publicId: milkAddedEventID,
                                  createdAt: date("2026-09-20T17:50:00.000+02:00"),
                                  updatedAt: date("2026-09-20T17:50:00.000+02:00"),
                                  createdBy: owner, updatedBy: owner,
                                  product: milkID, inventoryItem: milkItemID, kind: .added,
                                  quantity: decimal("2"), unit: .liter,
                                  fromLocationName: nil, toLocationName: "Hűtő",
                                  occurredAt: date("2026-09-20T17:50:00.000+02:00")),
                InventoryEventDTO(publicId: milkConsumedEventID,
                                  createdAt: date("2026-09-21T07:30:00.000+02:00"),
                                  updatedAt: date("2026-09-21T07:30:00.000+02:00"),
                                  createdBy: anna, updatedBy: anna,
                                  product: milkID, inventoryItem: milkItemID, kind: .consumed,
                                  quantity: decimal("0.5"), unit: .liter,
                                  fromLocationName: "Hűtő", toLocationName: nil,
                                  occurredAt: date("2026-09-21T07:30:00.000+02:00")),
                InventoryEventDTO(publicId: flourAddedEventID,
                                  createdAt: date("2026-03-05T11:05:00.000+01:00"),
                                  updatedAt: date("2026-03-05T11:05:00.000+01:00"),
                                  createdBy: owner, updatedBy: owner,
                                  product: flourID, inventoryItem: flourItemID, kind: .added,
                                  quantity: decimal("0.1"), unit: .kilogram,
                                  fromLocationName: nil, toLocationName: nil,
                                  occurredAt: date("2026-03-05T11:05:00.000+01:00")),
                InventoryEventDTO(publicId: milkDeletedEventID,
                                  createdAt: date("2026-09-10T20:00:00.000+02:00"),
                                  updatedAt: date("2026-09-10T20:00:00.000+02:00"),
                                  createdBy: anna, updatedBy: anna,
                                  product: milkID, inventoryItem: nil, kind: .deleted,
                                  quantity: decimal("1"), unit: .liter,
                                  fromLocationName: "Hűtő", toLocationName: nil,
                                  occurredAt: date("2026-09-10T20:00:00.000+02:00")),
            ],
            shoppingListItems: [
                ShoppingListItemDTO(publicId: milkListItemID,
                                    createdAt: date("2026-09-18T19:00:00.000+02:00"),
                                    updatedAt: date("2026-09-18T19:00:00.000+02:00"),
                                    createdBy: anna, updatedBy: anna,
                                    list: weeklyListID, product: milkID, customName: nil,
                                    quantity: decimal("2"), unit: .liter, note: "Laktózmentes",
                                    deadline: date("2026-09-26T00:00:00.000+02:00"),
                                    isPurchased: false, purchasedAt: nil, sortOrder: 0,
                                    shoppingLocation: sparID),
                ShoppingListItemDTO(publicId: breadListItemID,
                                    createdAt: date("2026-09-18T19:01:00.000+02:00"),
                                    updatedAt: date("2026-09-20T17:42:00.000+02:00"),
                                    createdBy: anna, updatedBy: owner,
                                    list: weeklyListID, product: nil, customName: "Kenyér",
                                    quantity: decimal("1"), unit: .piece, note: nil, deadline: nil,
                                    isPurchased: true,
                                    purchasedAt: date("2026-09-20T17:42:00.000+02:00"),
                                    sortOrder: 1, shoppingLocation: nil),
            ]
        )
        let manifest = ArchiveManifest(schemaVersion: 1,
                                       exportedAt: date("2026-09-24T10:00:00.000+02:00"),
                                       appVersion: "1.0 (1)", locale: "hu-HU",
                                       timeZone: "Europe/Budapest", spaceName: "Otthon",
                                       spaceKind: .household, counts: data.counts)
        return ArchiveContents(manifest: manifest, data: data)
    }()

    private static func id(_ text: String) -> UUID {
        guard let id = UUID(uuidString: text) else { preconditionFailure("bad sample UUID \(text)") }
        return id
    }

    private static func date(_ text: String) -> Date {
        guard let date = ArchiveDate.parse(text) else { preconditionFailure("bad sample date \(text)") }
        return date
    }

    private static func decimal(_ text: String) -> DecimalString {
        guard let value = DecimalString.parse(text) else { preconditionFailure("bad sample decimal \(text)") }
        return DecimalString(value)
    }
}
#endif
