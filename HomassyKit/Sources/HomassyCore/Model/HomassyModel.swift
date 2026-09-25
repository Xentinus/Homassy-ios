import CoreData
import Foundation

/// The Homassy Core Data model, built in code. Use this single instance for every container:
/// several model instances claiming the same classes confuse `NSManagedObject.entity()`.
public enum HomassyModel {
    public static var shared: NSManagedObjectModel { storage.model }

    /// `NSManagedObjectModel` is not Sendable. The model is never mutated after `build()`, so sharing it is safe.
    private struct Storage: @unchecked Sendable { let model: NSManagedObjectModel }
    private static let storage = Storage(model: build())

    private static func build() -> NSManagedObjectModel {
        let space = entity(Space.self, [
            string("name", default: ""),
            string("kindRaw", default: SpaceKind.personal.rawValue),
            int32("sortOrder"),
        ])
        let member = entity(Member.self, [
            string("userRecordName"),
            string("displayName"),
            string("colorSeed"),
            binary("avatar"),
            string("colorKey"),        // P5-03: hand-picked MemberColor key; nil = automatic from colorSeed
        ])
        let product = entity(Product.self, [
            string("name", default: ""),
            string("brand"),
            string("category"),
            string("barcode"),
            string("defaultUnitRaw", default: MeasureUnit.piece.rawValue),
            bool("isFavorite", default: false),
            string("notes"),
            binary("image"),
            string("url"),
        ])
        let storageLocation = entity(StorageLocation.self, [
            string("name", default: ""),
            string("color"),
            int32("sortOrder"),
            bool("isFreezer", default: false),
        ])
        let inventoryItem = entity(InventoryItem.self, [
            decimal("quantity", default: 0),
            string("unitRaw", default: MeasureUnit.piece.rawValue),
            date("expiresAt"),
            date("purchasedAt"),
            decimal("price"),
            string("currency"),
            bool("isFullyConsumed", default: false),
            date("consumedAt"),
        ])
        let consumptionLog = entity(ConsumptionLog.self, [
            decimal("quantity", default: 0),
            decimal("remaining", default: 0),
            date("consumedAt"),
        ])
        let inventoryEvent = entity(InventoryEvent.self, [
            string("kindRaw", default: InventoryEventKind.added.rawValue),
            decimal("quantity", default: 0),
            string("unitRaw", default: MeasureUnit.piece.rawValue),
            string("fromLocationName"),
            string("toLocationName"),
            date("occurredAt"),
        ])
        let purchaseRecord = entity(PurchaseRecord.self, [
            decimal("quantity", default: 0),
            string("unitRaw", default: MeasureUnit.piece.rawValue),
            decimal("price"),
            string("currency"),
            date("purchasedAt"),
        ])
        let shoppingLocation = entity(ShoppingLocation.self, [
            string("mapItemIdentifier"),
            string("name", default: ""),
            double("latitude"),
            double("longitude"),
            date("lastUsedAt"),
        ])
        let shoppingList = entity(ShoppingList.self, [
            string("name", default: ""),
            string("color"),
            int32("sortOrder"),
        ])
        let shoppingListItem = entity(ShoppingListItem.self, [
            string("customName"),
            decimal("quantity", default: 1),
            string("unitRaw", default: MeasureUnit.piece.rawValue),
            string("note"),
            date("deadline"),
            bool("isPurchased", default: false),
            date("purchasedAt"),
            int32("sortOrder"),
        ])

        // Space owns everything (cascade). Children point back with nullify.
        relate(space, "members", toMany: true, rule: .cascadeDeleteRule, member, "space", toMany: false, rule: .nullifyDeleteRule)
        relate(space, "products", toMany: true, rule: .cascadeDeleteRule, product, "space", toMany: false, rule: .nullifyDeleteRule)
        relate(space, "storageLocations", toMany: true, rule: .cascadeDeleteRule, storageLocation, "space", toMany: false, rule: .nullifyDeleteRule)
        relate(space, "shoppingLocations", toMany: true, rule: .cascadeDeleteRule, shoppingLocation, "space", toMany: false, rule: .nullifyDeleteRule)
        relate(space, "shoppingLists", toMany: true, rule: .cascadeDeleteRule, shoppingList, "space", toMany: false, rule: .nullifyDeleteRule)

        // Inventory.
        relate(product, "inventoryItems", toMany: true, rule: .cascadeDeleteRule, inventoryItem, "product", toMany: false, rule: .nullifyDeleteRule)
        relate(inventoryItem, "consumptionLogs", toMany: true, rule: .cascadeDeleteRule, consumptionLog, "inventoryItem", toMany: false, rule: .nullifyDeleteRule)
        relate(storageLocation, "inventoryItems", toMany: true, rule: .nullifyDeleteRule, inventoryItem, "storageLocation", toMany: false, rule: .nullifyDeleteRule)
        relate(shoppingLocation, "inventoryItems", toMany: true, rule: .nullifyDeleteRule, inventoryItem, "shoppingLocation", toMany: false, rule: .nullifyDeleteRule)

        // History: the product owns it; a deleted stock item leaves its events behind.
        relate(product, "inventoryEvents", toMany: true, rule: .cascadeDeleteRule, inventoryEvent, "product", toMany: false, rule: .nullifyDeleteRule)
        relate(inventoryItem, "inventoryEvents", toMany: true, rule: .nullifyDeleteRule, inventoryEvent, "inventoryItem", toMany: false, rule: .nullifyDeleteRule)

        // Purchases (P4-05): the product owns them; a deleted store or stock item leaves them behind.
        relate(product, "purchaseRecords", toMany: true, rule: .cascadeDeleteRule, purchaseRecord, "product", toMany: false, rule: .nullifyDeleteRule)
        relate(shoppingLocation, "purchaseRecords", toMany: true, rule: .nullifyDeleteRule, purchaseRecord, "shoppingLocation", toMany: false, rule: .nullifyDeleteRule)
        relate(inventoryItem, "purchaseRecords", toMany: true, rule: .nullifyDeleteRule, purchaseRecord, "inventoryItem", toMany: false, rule: .nullifyDeleteRule)

        // Shopping.
        relate(shoppingList, "items", toMany: true, rule: .cascadeDeleteRule, shoppingListItem, "shoppingList", toMany: false, rule: .nullifyDeleteRule)
        relate(product, "shoppingListItems", toMany: true, rule: .nullifyDeleteRule, shoppingListItem, "product", toMany: false, rule: .nullifyDeleteRule)
        relate(shoppingLocation, "shoppingListItems", toMany: true, rule: .nullifyDeleteRule, shoppingListItem, "shoppingLocation", toMany: false, rule: .nullifyDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [space, member, product, storageLocation, inventoryItem, consumptionLog, inventoryEvent,
                          purchaseRecord, shoppingLocation, shoppingList, shoppingListItem]
        return model
    }

    // MARK: Builders

    private static func entity(_ type: NSManagedObject.Type, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = String(describing: type)
        entity.managedObjectClassName = NSStringFromClass(type)
        entity.properties = commonAttributes() + attributes
        return entity
    }

    private static func commonAttributes() -> [NSAttributeDescription] {
        [
            attribute("publicId", .UUIDAttributeType),
            date("createdAt"),
            date("updatedAt"),
            string("createdBy", default: ""),
            string("updatedBy", default: ""),
        ]
    }

    /// Every attribute is optional (a CloudKit requirement). Defaults are for new objects only.
    private static func attribute(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = value
        return attribute
    }

    private static func string(_ name: String, default value: String? = nil) -> NSAttributeDescription {
        attribute(name, .stringAttributeType, default: value)
    }

    private static func bool(_ name: String, default value: Bool) -> NSAttributeDescription {
        attribute(name, .booleanAttributeType, default: NSNumber(value: value))
    }

    private static func int32(_ name: String, default value: Int32 = 0) -> NSAttributeDescription {
        attribute(name, .integer32AttributeType, default: NSNumber(value: value))
    }

    private static func decimal(_ name: String, default value: Decimal? = nil) -> NSAttributeDescription {
        attribute(name, .decimalAttributeType, default: value.map { NSDecimalNumber(decimal: $0) })
    }

    private static func double(_ name: String) -> NSAttributeDescription {
        attribute(name, .doubleAttributeType)
    }

    private static func date(_ name: String) -> NSAttributeDescription {
        attribute(name, .dateAttributeType)
    }

    /// Stored as a CKAsset in CloudKit.
    private static func binary(_ name: String) -> NSAttributeDescription {
        let attribute = attribute(name, .binaryDataAttributeType)
        attribute.allowsExternalBinaryDataStorage = true
        return attribute
    }

    private static func relate(
        _ source: NSEntityDescription, _ name: String, toMany: Bool, rule: NSDeleteRule,
        _ destination: NSEntityDescription, _ inverseName: String, toMany inverseToMany: Bool, rule inverseRule: NSDeleteRule
    ) {
        let forward = relationship(name, to: destination, toMany: toMany, rule: rule)
        let inverse = relationship(inverseName, to: source, toMany: inverseToMany, rule: inverseRule)
        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        source.properties.append(forward)
        destination.properties.append(inverse)
    }

    private static func relationship(_ name: String, to destination: NSEntityDescription, toMany: Bool, rule: NSDeleteRule) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.isOptional = true
        relationship.isOrdered = false
        relationship.minCount = 0
        relationship.maxCount = toMany ? 0 : 1
        relationship.deleteRule = rule
        return relationship
    }
}
