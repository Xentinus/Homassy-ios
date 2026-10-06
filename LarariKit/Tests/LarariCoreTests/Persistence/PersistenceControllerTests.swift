import CloudKit
import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
struct PersistenceControllerTests {
    private let cloudMode = StoreMode.cloudKit(containerIdentifier: "iCloud.app.larari", appGroup: "group.app.larari")
    private let base = URL(filePath: "/tmp/larari-tests/Stores", directoryHint: .isDirectory)

    // MARK: Descriptions

    @Test func cloudKitDescriptionsArePrivateThenShared() throws {
        let descriptions = PersistenceController.makeDescriptions(mode: cloudMode, baseURL: base)
        try #require(descriptions.count == 2)
        let (privateDescription, sharedDescription) = (descriptions[0], descriptions[1])

        #expect(privateDescription.url == base.appending(path: "Private.sqlite"))
        #expect(sharedDescription.url == base.appending(path: "Shared.sqlite"))
        #expect(privateDescription.type == NSSQLiteStoreType)
        #expect(sharedDescription.type == NSSQLiteStoreType)
        #expect(privateDescription.cloudKitContainerOptions?.databaseScope == .private)
        #expect(sharedDescription.cloudKitContainerOptions?.databaseScope == .shared)
    }

    @Test func cloudKitDescriptionsEnableHistoryAndRemoteChange() {
        for description in PersistenceController.makeDescriptions(mode: cloudMode, baseURL: base) {
            #expect(description.cloudKitContainerOptions?.containerIdentifier == "iCloud.app.larari")
            #expect((description.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue == true)
            #expect((description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber)?.boolValue == true)
            #expect(description.shouldAddStoreAsynchronously == false)
        }
    }

    @Test func inMemoryDescriptionsAreDistinctAndLocal() throws {
        let descriptions = PersistenceController.makeDescriptions(mode: .inMemory, baseURL: base)
        try #require(descriptions.count == 2)
        #expect(descriptions[0].url?.path == "/dev/null/private")
        #expect(descriptions[1].url?.path == "/dev/null/shared")
        for description in descriptions {
            #expect(description.type == NSInMemoryStoreType)
            #expect(description.cloudKitContainerOptions == nil)
        }
    }

    @Test func sqliteDescriptionsAreLocalWithHistory() throws {
        let directory = URL(filePath: "/tmp/larari-tests/sqlite", directoryHint: .isDirectory)
        let descriptions = PersistenceController.makeDescriptions(mode: .sqlite(directory: directory), baseURL: directory)
        try #require(descriptions.count == 2)
        #expect(descriptions[0].url == directory.appending(path: "Private.sqlite"))
        #expect(descriptions[1].url == directory.appending(path: "Shared.sqlite"))
        for description in descriptions {
            #expect(description.type == NSSQLiteStoreType)
            #expect(description.cloudKitContainerOptions == nil)
            #expect((description.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue == true)
            #expect((description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber)?.boolValue == true)
        }
    }

    @Test func localDevelopmentModeIsSQLiteInApplicationSupport() throws {
        let expected = URL.applicationSupportDirectory.appending(path: "Larari", directoryHint: .isDirectory)
        #expect(StoreMode.localDevelopmentDirectory == expected)
        guard case let .sqlite(directory) = StoreMode.localDevelopment else {
            Issue.record("localDevelopment is not a SQLite mode")
            return
        }
        #expect(directory == expected)
        let descriptions = PersistenceController.makeDescriptions(mode: .localDevelopment, baseURL: directory)
        try #require(descriptions.count == 2)
        #expect(descriptions.allSatisfy { $0.cloudKitContainerOptions == nil })
        #expect(descriptions[0].url == expected.appending(path: "Private.sqlite"))
    }

    @Test func productionModeUsesTheLarariIdentifiers() {
        guard case let .cloudKit(containerIdentifier, appGroup) = StoreMode.production else {
            Issue.record("production is not a CloudKit mode")
            return
        }
        #expect(containerIdentifier == "iCloud.app.larari")
        #expect(appGroup == "group.app.larari")
    }

    // MARK: Loading

    @Test func inMemoryModeLoadsTwoDistinctStores() throws {
        let controller = try PersistenceController(mode: .inMemory)
        let stores = controller.container.persistentStoreCoordinator.persistentStores
        #expect(stores.count == 2)
        #expect(controller.privateStore !== controller.sharedStore)
        #expect(controller.privateStore.url?.lastPathComponent == "private")
        #expect(controller.sharedStore.url?.lastPathComponent == "shared")
        #expect(controller.privateStore.type == NSInMemoryStoreType)
        #expect(stores.first === controller.privateStore)
    }

    @Test func sqliteModeLoadsTwoDistinctFileStores() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "larari-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try PersistenceController(mode: .sqlite(directory: directory))
        #expect(controller.container.persistentStoreCoordinator.persistentStores.count == 2)
        #expect(controller.privateStore !== controller.sharedStore)
        #expect(controller.privateStore.type == NSSQLiteStoreType)
        #expect(controller.privateStore.url == directory.appending(path: "Private.sqlite"))
        #expect(controller.sharedStore.url == directory.appending(path: "Shared.sqlite"))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Private.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Shared.sqlite").path))
    }

    @Test func sqliteModeRecordsPersistentHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "larari-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try PersistenceController(mode: .sqlite(directory: directory))
        let context = controller.viewContext
        let space = Space(context: context)
        context.assign(space, to: controller.sharedStore)
        try context.save()

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: .distantPast)
        request.affectedStores = [controller.sharedStore]
        let result = try context.execute(request) as? NSPersistentHistoryResult
        let transactions = try #require(result?.result as? [NSPersistentHistoryTransaction])
        #expect(!transactions.isEmpty)
        #expect(transactions.last?.author == PersistenceController.transactionAuthor)
    }

    @Test func containerUsesTheSharedModel() throws {
        let controller = try PersistenceController(mode: .inMemory)
        #expect(controller.container.managedObjectModel === LarariModel.shared)
    }

    @Test func viewContextIsConfiguredForCloudKitMerging() throws {
        let controller = try PersistenceController(mode: .inMemory)
        let context = controller.viewContext
        #expect(context === controller.container.viewContext)
        #expect(context.automaticallyMergesChangesFromParent)
        #expect((context.mergePolicy as? NSMergePolicy)?.mergeType == .mergeByPropertyObjectTrumpMergePolicyType)
        #expect(context.transactionAuthor == "app")
        #expect(PersistenceController.transactionAuthor == "app")
        #expect(context.name == "viewContext")
    }

    // MARK: Store assignment

    @Test func objectAssignedToSharedStoreIsSavedThere() throws {
        let controller = try PersistenceController(mode: .inMemory)
        let context = controller.viewContext
        let space = Space(context: context)
        space.name = "Otthon"
        space.kind = .household
        context.assign(space, to: controller.sharedStore)
        try context.save()

        #expect(space.objectID.persistentStore === controller.sharedStore)
        let inShared = Space.makeFetchRequest()
        inShared.affectedStores = [controller.sharedStore]
        #expect(try context.count(for: inShared) == 1)
        let inPrivate = Space.makeFetchRequest()
        inPrivate.affectedStores = [controller.privateStore]
        #expect(try context.count(for: inPrivate) == 0)
    }

    @Test func unassignedObjectsLandInThePrivateStore() throws {
        let controller = try PersistenceController(mode: .inMemory)
        let context = controller.viewContext
        let space = Space(context: context)
        try context.save()
        #expect(space.objectID.persistentStore === controller.privateStore)
    }

    @Test func twoControllersDoNotShareData() throws {
        let first = try PersistenceController(mode: .inMemory)
        let second = try PersistenceController(mode: .inMemory)
        _ = Space(context: first.viewContext)
        try first.viewContext.save()
        #expect(try second.viewContext.count(for: Space.makeFetchRequest()) == 0)
    }

    // MARK: Preview

    @Test func previewIsSeededInBothStores() throws {
        let controller = PersistenceController.preview()
        let context = controller.viewContext

        let privateSpaces = Space.makeFetchRequest()
        privateSpaces.affectedStores = [controller.privateStore]
        let personal = try #require(try context.fetch(privateSpaces).first)
        #expect(personal.kind == .personal)

        let sharedSpaces = Space.makeFetchRequest()
        sharedSpaces.affectedStores = [controller.sharedStore]
        let household = try #require(try context.fetch(sharedSpaces).first)
        #expect(household.kind == .household)

        #expect(try context.count(for: Product.makeFetchRequest()) >= 3)
        #expect(try context.count(for: InventoryItem.makeFetchRequest()) >= 3)
        #expect(try context.count(for: ShoppingListItem.makeFetchRequest()) >= 1)
        #expect(personal.createdBy == PersistenceController.previewUserRecordName)
        #expect(!context.hasChanges)
    }
}
