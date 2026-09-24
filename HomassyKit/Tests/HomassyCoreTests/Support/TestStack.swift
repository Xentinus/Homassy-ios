import CoreData
import Foundation
@testable import HomassyCore

/// A single in-memory store built on the shared model. PersistenceController (P1-03) replaces this for two-store tests.
enum TestStack {
    @MainActor
    static func makeContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "HomassyModelTests", managedObjectModel: HomassyModel.shared)
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }
}
