import CoreData
import Foundation
import Testing
@testable import HomassyCore

/// A local-mode SQLite store written by an older model must open with the current one.
/// Core Data keeps the store's model in the file, so additive changes migrate automatically.
@MainActor
@Suite("Model upgrade")
struct ModelUpgradeTests {
    /// The model as it was before P2-06 added `InventoryEvent`. Its entities use plain `NSManagedObject`:
    /// a second model claiming the Homassy classes would break `+entity` for tests running in parallel.
    static func modelWithoutInventoryEvent() -> NSManagedObjectModel {
        let model = HomassyModel.shared.copy() as! NSManagedObjectModel
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = entity.properties.filter {
                ($0 as? NSRelationshipDescription)?.destinationEntity?.name != "InventoryEvent"
            }
        }
        model.entities = model.entities.filter { $0.name != "InventoryEvent" }
        return model
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
}
