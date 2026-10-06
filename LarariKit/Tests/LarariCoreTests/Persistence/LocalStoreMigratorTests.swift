import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
struct LocalStoreMigratorTests {
    let local = LocalAccountStatusProvider.userRecordName   // "_localDeveloper"
    let real = "_real"
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "larari-migrate-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private var source: URL { root.appending(path: "Larari", directoryHint: .isDirectory) }
    private var destination: URL { root.appending(path: "Group/Stores", directoryHint: .isDirectory) }

    /// Writes a local-mode store (Personal space + one product) and closes it.
    private func writeLocalStore() throws {
        let controller = try PersistenceController(mode: .sqlite(directory: source))
        let store = SpaceStore(persistence: controller, sharing: ContainerShareLookup(container: controller.container))
        let personal = try store.bootstrapPersonalSpace(userRecordName: local)
        let milk = store.insert(Product.self, in: personal, by: local)
        milk.name = "Milk"
        milk.space = personal
        try controller.viewContext.save()
        try close(controller)
    }

    private func close(_ controller: PersistenceController) throws {
        let coordinator = controller.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
    }

    @Test func nothingToMigrateWithoutALocalStore() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try LocalStoreMigrator.migrate(from: source, to: destination) == .nothingToMigrate)
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "Private.sqlite").path))
    }

    @Test func migratesThePrivateStoreAndMovesTheLocalFolderAside() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLocalStore()

        let result = try LocalStoreMigrator.migrate(from: source, to: destination)

        guard case let .migrated(count) = result else { Issue.record("expected .migrated, got \(result)"); return }
        #expect(count >= 2)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Larari" + LocalStoreMigrator.backupSuffix).path))

        let migrated = try PersistenceController(mode: .sqlite(directory: destination))
        let products = try migrated.viewContext.fetch(Product.makeFetchRequest())
        #expect(products.map(\.name) == ["Milk"])
        #expect(products.first?.objectID.persistentStore === migrated.privateStore)
        #expect(try migrated.viewContext.fetch(Space.makeFetchRequest()).first?.publicId == SpaceStore.personalSpaceID(for: local))
    }

    @Test func aSecondRunDoesNothing() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLocalStore()
        _ = try LocalStoreMigrator.migrate(from: source, to: destination)
        #expect(try LocalStoreMigrator.migrate(from: source, to: destination) == .nothingToMigrate)
    }

    @Test func anExistingCloudStoreIsNeverOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLocalStore()
        try close(try PersistenceController(mode: .sqlite(directory: destination)))   // a cloud store already exists

        #expect(try LocalStoreMigrator.migrate(from: source, to: destination) == .destinationExists)
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "Private.sqlite").path))
    }

    @Test func adoptRewritesStampsAndRekeysThePersonalSpace() throws {
        let controller = try PersistenceController(mode: .inMemory)
        let store = SpaceStore(persistence: controller, sharing: ContainerShareLookup(container: controller.container))
        let personal = try store.bootstrapPersonalSpace(userRecordName: local)
        let household = try SharingFixtures.insertSpace(named: "Test flat", into: controller.privateStore,
                                                        of: controller, by: local)
        let member = store.insert(Member.self, in: household, by: local)
        member.space = household
        member.userRecordName = local
        member.colorSeed = local
        try controller.viewContext.save()

        let changed = try LocalStoreMigrator.adoptLocalData(in: controller, to: real)

        #expect(changed >= 3)
        #expect(personal.publicId == SpaceStore.personalSpaceID(for: real))
        #expect(personal.createdBy == real && personal.updatedBy == real)
        #expect(household.createdBy == real)
        #expect(member.userRecordName == real && member.colorSeed == real)
        #expect(try store.bootstrapPersonalSpace(userRecordName: real) === personal)   // no second Personal space
        #expect(try LocalStoreMigrator.adoptLocalData(in: controller, to: real) == 0)   // idempotent
    }
}
