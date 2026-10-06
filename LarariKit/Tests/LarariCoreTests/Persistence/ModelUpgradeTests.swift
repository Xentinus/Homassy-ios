import CoreData
import Foundation
import Testing
@testable import LarariCore

/// A local-mode SQLite store written by an older model must open with the current one.
/// Core Data keeps the store's model in the file, so additive changes migrate automatically.
@MainActor
@Suite("Model upgrade")
struct ModelUpgradeTests {
    /// The model as it was before P2-06 added `InventoryEvent`. Its entities use plain `NSManagedObject`:
    /// a second model claiming the Larari classes would break `+entity` for tests running in parallel.
    static func modelWithoutInventoryEvent() -> NSManagedObjectModel {
        let model = LarariModel.shared.copy() as! NSManagedObjectModel
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = entity.properties.filter {
                ($0 as? NSRelationshipDescription)?.destinationEntity?.name != "InventoryEvent"
            }
        }
        model.entities = model.entities.filter { $0.name != "InventoryEvent" }
        return model
    }

    /// The model as it was before P4-05 added `PurchaseRecord`.
    static func modelWithoutPurchaseRecord() -> NSManagedObjectModel {
        let model = LarariModel.shared.copy() as! NSManagedObjectModel
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = entity.properties.filter {
                ($0 as? NSRelationshipDescription)?.destinationEntity?.name != "PurchaseRecord"
            }
        }
        model.entities = model.entities.filter { $0.name != "PurchaseRecord" }
        return model
    }

    /// The model as it was from P2-06 to P2-09: Product still had `isEatable` and no `url`.
    static func modelWithEatableAndNoURL() -> NSManagedObjectModel {
        let model = LarariModel.shared.copy() as! NSManagedObjectModel
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        let product = model.entitiesByName["Product"]!
        let eatable = NSAttributeDescription()
        eatable.name = "isEatable"
        eatable.attributeType = .booleanAttributeType
        eatable.isOptional = true
        eatable.defaultValue = NSNumber(value: true)
        product.properties = product.properties.filter { $0.name != "url" } + [eatable]
        return model
    }

    @Test("A store with isEatable and without url opens and keeps its products")
    func droppingEatableAndAddingURLMigratesTheLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ModelUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = Self.modelWithEatableAndNoURL()
        for fileName in [PersistenceController.privateFileName, PersistenceController.sharedFileName] {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
            _ = try coordinator.addPersistentStore(type: .sqlite, at: directory.appending(path: fileName),
                                                   options: [NSPersistentHistoryTrackingKey: true as NSNumber])
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let product = NSEntityDescription.insertNewObject(forEntityName: "Product", into: context)
            product.setValue("Milk", forKey: "name")
            product.setValue(false, forKey: "isEatable")
            product.setValue(UUID(), forKey: "publicId")
            try context.save()
        }

        let controller = try PersistenceController(mode: .sqlite(directory: directory))
        let products = try controller.viewContext.fetch(Product.makeFetchRequest())
        #expect(products.count == 2)
        #expect(products.allSatisfy { $0.name == "Milk" && $0.url == nil })
    }

    @Test("A P1-era local store opens after InventoryEvent was added and keeps its data")
    func addingInventoryEventMigratesTheLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ModelUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = Self.modelWithoutInventoryEvent()
        #expect(old.entitiesByName["InventoryEvent"] == nil)
        for fileName in [PersistenceController.privateFileName, PersistenceController.sharedFileName] {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
            _ = try coordinator.addPersistentStore(type: .sqlite, at: directory.appending(path: fileName),
                                                   options: [NSPersistentHistoryTrackingKey: true as NSNumber])
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let product = NSEntityDescription.insertNewObject(forEntityName: "Product", into: context)
            product.setValue("Milk", forKey: "name")
            product.setValue(UUID(), forKey: "publicId")
            try context.save()
        }

        let controller = try PersistenceController(mode: .sqlite(directory: directory))
        let context = controller.viewContext
        #expect(try context.count(for: Product.makeFetchRequest()) == 2)

        let milk = try #require(try context.fetch(Product.makeFetchRequest()).first)
        let event = InventoryEvent(context: context)
        event.kind = .added
        event.product = milk
        context.assign(event, to: try #require(milk.objectID.persistentStore))
        try context.save()
        #expect(milk.inventoryEventSet == [event])
    }

    @Test("A store from before PurchaseRecord opens and keeps its stock")
    func addingPurchaseRecordMigratesTheLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ModelUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = Self.modelWithoutPurchaseRecord()
        #expect(old.entitiesByName["PurchaseRecord"] == nil)
        for fileName in [PersistenceController.privateFileName, PersistenceController.sharedFileName] {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
            _ = try coordinator.addPersistentStore(type: .sqlite, at: directory.appending(path: fileName),
                                                   options: [NSPersistentHistoryTrackingKey: true as NSNumber])
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let product = NSEntityDescription.insertNewObject(forEntityName: "Product", into: context)
            product.setValue("Milk", forKey: "name")
            product.setValue(UUID(), forKey: "publicId")
            let item = NSEntityDescription.insertNewObject(forEntityName: "InventoryItem", into: context)
            item.setValue(UUID(), forKey: "publicId")
            item.setValue(product, forKey: "product")
            item.setValue(NSDecimalNumber(string: "459"), forKey: "price")
            try context.save()
        }

        let controller = try PersistenceController(mode: .sqlite(directory: directory))
        let context = controller.viewContext
        let items = try context.fetch(NSFetchRequest<InventoryItem>(entityName: "InventoryItem"))
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.price == 459 && $0.purchaseRecordSet.isEmpty })

        let milk = try #require(items.first?.product)
        let record = PurchaseRecord(context: context)
        record.product = milk
        record.price = 459
        context.assign(record, to: try #require(milk.objectID.persistentStore))
        try context.save()
        #expect(milk.purchaseRecordSet == [record])
    }
}
