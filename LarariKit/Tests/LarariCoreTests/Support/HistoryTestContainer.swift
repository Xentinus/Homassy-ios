import CoreData
import Foundation
@testable import LarariCore

@MainActor
enum HistoryTestContainer {
    static let importAuthor = "NSCloudKitMirroringDelegate.import"

    /// A fresh `.sqlite` PersistenceController in its own temp directory. Returns its container
    /// (an `NSPersistentCloudKitContainer`, which is an `NSPersistentContainer`) and its private store.
    static func make() throws -> (NSPersistentContainer, NSPersistentStore) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)",
                                                                         directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let persistence = try PersistenceController(mode: .sqlite(directory: directory))
        persistence.viewContext.automaticallyMergesChangesFromParent = true
        // viewContext.transactionAuthor is already "app" (step 6 of this task sets it in PersistenceController).
        return (persistence.container, persistence.privateStore)
    }

    /// Saves a Product the way a CloudKit import would.
    @discardableResult
    static func importProduct(into container: NSPersistentContainer, name: String, publicId: UUID = UUID(),
                              updatedBy: String, updatedAt: Date = .now) throws -> UUID {
        let context = container.newBackgroundContext()
        context.transactionAuthor = importAuthor
        try context.performAndWait {
            let product = NSEntityDescription.insertNewObject(forEntityName: "Product", into: context) as! Product
            product.publicId = publicId
            product.name = name
            product.createdAt = updatedAt
            product.createdBy = updatedBy
            product.updatedAt = updatedAt
            product.updatedBy = updatedBy
            try context.save()
        }
        return publicId
    }

    static func products(with publicId: UUID, in container: NSPersistentContainer) throws -> [Product] {
        let request = NSFetchRequest<Product>(entityName: "Product")
        request.predicate = NSPredicate(format: "publicId == %@", publicId as CVarArg)
        return try container.viewContext.fetch(request)
    }
}
