import CoreData
import Testing
@testable import LarariCore

/// The rules NSPersistentCloudKitContainer enforces when it loads a CloudKit-backed store.
/// This checks them without CloudKit, so a bad model fails in `swift test` instead of at launch.
@MainActor
struct CloudKitModelRulesTests {
    private var entities: [NSEntityDescription] { LarariModel.shared.entities }

    @Test func noUniquenessConstraints() {
        for entity in entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") has uniqueness constraints")
        }
    }

    @Test func everyAttributeIsOptionalOrDefaulted() {
        for entity in entities {
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        "\(entity.name ?? "?").\(attribute.name) is required without a default")
            }
        }
    }

    @Test func everyRelationshipIsOptionalUnorderedWithInverse() {
        for entity in entities {
            for relationship in entity.relationshipsByName.values {
                let label = "\(entity.name ?? "?").\(relationship.name)"
                #expect(relationship.isOptional, "\(label) is not optional")
                #expect(!relationship.isOrdered, "\(label) is ordered")
                #expect(relationship.deleteRule != .denyDeleteRule, "\(label) uses Deny")
                let inverse = relationship.inverseRelationship
                #expect(inverse != nil, "\(label) has no inverse")
                #expect(inverse?.inverseRelationship === relationship, "\(label) inverse does not point back")
                #expect(inverse?.destinationEntity === entity, "\(label) inverse has the wrong destination")
            }
        }
    }

    @Test func everyEntityHasTheCommonAttributes() {
        for entity in entities {
            let attributes = entity.attributesByName
            #expect(attributes["publicId"]?.attributeType == .UUIDAttributeType, "\(entity.name ?? "?").publicId")
            #expect(attributes["createdAt"]?.attributeType == .dateAttributeType)
            #expect(attributes["updatedAt"]?.attributeType == .dateAttributeType)
            #expect(attributes["createdBy"]?.defaultValue as? String == "")
            #expect(attributes["updatedBy"]?.defaultValue as? String == "")
        }
    }

    @Test func quantitiesAreDecimalAndImagesAreExternal() {
        let model = LarariModel.shared.entitiesByName
        let decimals = [("InventoryItem", "quantity"), ("InventoryItem", "price"),
                        ("ConsumptionLog", "quantity"), ("ConsumptionLog", "remaining"), ("InventoryEvent", "quantity"),
                        ("PurchaseRecord", "quantity"), ("PurchaseRecord", "price"), ("ShoppingListItem", "quantity")]
        for (entity, name) in decimals {
            #expect(model[entity]?.attributesByName[name]?.attributeType == .decimalAttributeType, "\(entity).\(name)")
        }
        for (entity, name) in [("Product", "image"), ("Member", "avatar")] {
            let attribute = model[entity]?.attributesByName[name]
            #expect(attribute?.attributeType == .binaryDataAttributeType, "\(entity).\(name)")
            #expect(attribute?.allowsExternalBinaryDataStorage == true, "\(entity).\(name)")
        }
    }

    @Test("Product has a link and no eatable flag (user, 2026-09-24)")
    func productAttributes() {
        let attributes = LarariModel.shared.entitiesByName["Product"]?.attributesByName ?? [:]
        #expect(attributes["url"]?.attributeType == .stringAttributeType)
        #expect(attributes["url"]?.isOptional == true)
        #expect(attributes["isEatable"] == nil)
    }

    @Test func deleteRulesMatchTheSpec() {
        let model = LarariModel.shared.entitiesByName
        func rule(_ entity: String, _ relationship: String) -> NSDeleteRule? {
            model[entity]?.relationshipsByName[relationship]?.deleteRule
        }
        for name in ["members", "products", "storageLocations", "shoppingLocations", "shoppingLists"] {
            #expect(rule("Space", name) == .cascadeDeleteRule, "Space.\(name)")
        }
        #expect(rule("Product", "inventoryItems") == .cascadeDeleteRule)
        #expect(rule("InventoryItem", "consumptionLogs") == .cascadeDeleteRule)
        #expect(rule("Product", "inventoryEvents") == .cascadeDeleteRule)
        #expect(rule("InventoryItem", "inventoryEvents") == .nullifyDeleteRule)
        #expect(rule("InventoryEvent", "product") == .nullifyDeleteRule)
        #expect(rule("InventoryEvent", "inventoryItem") == .nullifyDeleteRule)
        #expect(rule("Product", "purchaseRecords") == .cascadeDeleteRule)
        #expect(rule("ShoppingLocation", "purchaseRecords") == .nullifyDeleteRule)
        #expect(rule("InventoryItem", "purchaseRecords") == .nullifyDeleteRule)
        #expect(rule("PurchaseRecord", "product") == .nullifyDeleteRule)
        #expect(rule("PurchaseRecord", "shoppingLocation") == .nullifyDeleteRule)
        #expect(rule("PurchaseRecord", "inventoryItem") == .nullifyDeleteRule)
        #expect(rule("ShoppingList", "items") == .cascadeDeleteRule)
        #expect(rule("Product", "shoppingListItems") == .nullifyDeleteRule)
        #expect(rule("StorageLocation", "inventoryItems") == .nullifyDeleteRule)
        #expect(rule("ShoppingLocation", "inventoryItems") == .nullifyDeleteRule)
        #expect(rule("ShoppingLocation", "shoppingListItems") == .nullifyDeleteRule)
        #expect(rule("InventoryItem", "storageLocation") == .nullifyDeleteRule)
        #expect(rule("InventoryItem", "shoppingLocation") == .nullifyDeleteRule)
        #expect(rule("ShoppingListItem", "product") == .nullifyDeleteRule)
        #expect(rule("ShoppingListItem", "shoppingLocation") == .nullifyDeleteRule)
    }
}
