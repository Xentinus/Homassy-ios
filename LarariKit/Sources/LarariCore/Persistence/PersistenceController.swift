import CloudKit
import CoreData
import Foundation

public enum StoreMode: Sendable {
    case cloudKit(containerIdentifier: String, appGroup: String)
    case inMemory
    case sqlite(directory: URL)

    public static let production = StoreMode.cloudKit(containerIdentifier: "iCloud.app.larari",
                                                      appGroup: "group.app.larari")

    /// `<Application Support>/Larari`. Local mode (no CLOUDKIT_ENABLED) keeps its stores here.
    public static var localDevelopmentDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Larari", directoryHint: .isDirectory)
    }

    /// The app's store in local mode: SQLite with history, no CloudKit, no entitlements.
    public static var localDevelopment: StoreMode { .sqlite(directory: localDevelopmentDirectory) }
}

public enum PersistenceError: Error, Equatable {
    case appGroupUnavailable(String)
    case storeLoadFailed(String)
    case storeMissing(String)
}

/// Owns the NSPersistentCloudKitContainer and its two stores.
/// Private.sqlite ↔ CloudKit private database (Personal space + households the user owns).
/// Shared.sqlite ↔ CloudKit shared database (households the user joined).
@MainActor
public final class PersistenceController {
    public static let transactionAuthor = "app"
    public static let initializeSchemaArgument = "-initializeCloudKitSchema"
    public static let previewUserRecordName = "_preview-user"

    static let privateFileName = "Private.sqlite"
    static let sharedFileName = "Shared.sqlite"

    public let container: NSPersistentCloudKitContainer
    public let privateStore: NSPersistentStore
    public let sharedStore: NSPersistentStore
    public var viewContext: NSManagedObjectContext { container.viewContext }

    public init(mode: StoreMode) throws {
        let baseURL = try Self.storeDirectory(for: mode)
        let descriptions = Self.makeDescriptions(mode: mode, baseURL: baseURL)

        let container = NSPersistentCloudKitContainer(name: "Larari", managedObjectModel: LarariModel.shared)
        container.persistentStoreDescriptions = descriptions

        var loadErrors: [String] = []
        container.loadPersistentStores { description, error in
            if let error {
                loadErrors.append("\(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
            }
        }
        guard loadErrors.isEmpty else {
            throw PersistenceError.storeLoadFailed(loadErrors.joined(separator: "\n"))
        }

        let stores = container.persistentStoreCoordinator.persistentStores
        func store(matching description: NSPersistentStoreDescription) -> NSPersistentStore? {
            stores.first { $0.url?.lastPathComponent == description.url?.lastPathComponent }
        }
        guard let privateStore = store(matching: descriptions[0]) else { throw PersistenceError.storeMissing("private") }
        guard let sharedStore = store(matching: descriptions[1]) else { throw PersistenceError.storeMissing("shared") }

        let context = container.viewContext
        context.name = "viewContext"
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Self.transactionAuthor

        self.container = container
        self.privateStore = privateStore
        self.sharedStore = sharedStore

        #if DEBUG
        if case .cloudKit = mode, ProcessInfo.processInfo.arguments.contains(Self.initializeSchemaArgument) {
            try container.initializeCloudKitSchema(options: [])
        }
        #endif
    }

    /// Builds the two store descriptions, private first, without touching the file system.
    public static func makeDescriptions(mode: StoreMode, baseURL: URL) -> [NSPersistentStoreDescription] {
        switch mode {
        case .inMemory:
            return ["private", "shared"].map { name in
                let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null").appending(path: name))
                description.type = NSInMemoryStoreType
                description.shouldAddStoreAsynchronously = false
                return description
            }
        case .sqlite:
            return [privateFileName, sharedFileName].map { localSQLiteDescription(baseURL.appending(path: $0)) }
        case let .cloudKit(containerIdentifier, _):
            func cloudDescription(_ fileName: String, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
                let description = localSQLiteDescription(baseURL.appending(path: fileName))
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                options.databaseScope = scope
                description.cloudKitContainerOptions = options
                return description
            }
            return [cloudDescription(privateFileName, scope: .private),
                    cloudDescription(sharedFileName, scope: .shared)]
        }
    }

    /// A SQLite description with history tracking and remote-change notifications on, and no CloudKit options.
    private static func localSQLiteDescription(_ url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    /// `<App Group>/Stores/` for CloudKit mode, or the given directory for SQLite mode, created if needed.
    /// It is unused for in-memory mode.
    public static func storeDirectory(for mode: StoreMode) throws -> URL {
        switch mode {
        case .inMemory:
            return URL(fileURLWithPath: "/dev/null")
        case let .sqlite(directory):
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        case let .cloudKit(_, appGroup):
            guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                throw PersistenceError.appGroupUnavailable(appGroup)
            }
            let directory = groupURL.appending(path: "Stores", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    // MARK: Preview

    /// An in-memory controller with a Personal space in the private store and a household in the shared store.
    public static func preview() -> PersistenceController {
        do {
            let controller = try PersistenceController(mode: .inMemory)
            try controller.seedPreviewData(now: .now)
            return controller
        } catch {
            fatalError("Could not build the preview store: \(error)")
        }
    }

    func seedPreviewData(now: Date) throws {
        let context = viewContext
        let user = Self.previewUserRecordName
        let day: TimeInterval = 86_400

        func adopt<T: LarariEntity>(_ object: T, into store: NSPersistentStore) -> T {
            context.assign(object, to: store)
            object.stamp(by: user, now: now)
            return object
        }

        // Personal space (private store).
        let personal = adopt(Space(context: context), into: privateStore)
        personal.name = "Personal"
        personal.kind = .personal
        personal.sortOrder = 0

        let fridge = adopt(StorageLocation(context: context), into: privateStore)
        fridge.name = "Fridge"
        fridge.sortOrder = 0
        fridge.space = personal

        let pantry = adopt(StorageLocation(context: context), into: privateStore)
        pantry.name = "Pantry"
        pantry.sortOrder = 1
        pantry.space = personal

        let milk = adopt(Product(context: context), into: privateStore)
        milk.name = "Milk"
        milk.defaultUnit = .liter
        milk.category = "Dairy"
        milk.space = personal

        let bread = adopt(Product(context: context), into: privateStore)
        bread.name = "Bread"
        bread.defaultUnit = .piece
        bread.category = "Bakery"
        bread.space = personal

        let milkItem = adopt(InventoryItem(context: context), into: privateStore)
        milkItem.product = milk
        milkItem.quantity = 2
        milkItem.unit = .liter
        milkItem.expiresAt = now.addingTimeInterval(2 * day)
        milkItem.purchasedAt = now.addingTimeInterval(-day)
        milkItem.storageLocation = fridge

        let breadItem = adopt(InventoryItem(context: context), into: privateStore)
        breadItem.product = bread
        breadItem.quantity = 1
        breadItem.unit = .piece
        breadItem.expiresAt = now.addingTimeInterval(day)
        breadItem.storageLocation = pantry

        let groceries = adopt(ShoppingList(context: context), into: privateStore)
        groceries.name = "Groceries"
        groceries.space = personal

        let eggs = adopt(ShoppingListItem(context: context), into: privateStore)
        eggs.customName = "Eggs"
        eggs.quantity = 10
        eggs.unit = .piece
        eggs.shoppingList = groceries

        // A household (shared store), as if the user had joined it.
        let household = adopt(Space(context: context), into: sharedStore)
        household.name = "Home"
        household.kind = .household
        household.sortOrder = 1

        let coffee = adopt(Product(context: context), into: sharedStore)
        coffee.name = "Coffee"
        coffee.defaultUnit = .gram
        coffee.space = household

        let coffeeItem = adopt(InventoryItem(context: context), into: sharedStore)
        coffeeItem.product = coffee
        coffeeItem.quantity = 500
        coffeeItem.unit = .gram
        coffeeItem.expiresAt = now.addingTimeInterval(90 * day)

        try context.save()
    }
}
