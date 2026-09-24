import CoreData
import Foundation
import Testing
@testable import HomassyCore

extension ServiceTestEnvironment {
    func storageService(canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) -> StorageLocationService {
        StorageLocationService(spaceStore: spaceStore, context: context, userRecordName: Self.user, canEdit: canEdit)
    }

    /// Raw item insert for tests that run before InventoryService exists.
    @discardableResult
    func makeItem(_ product: Product, quantity: Decimal = 1, location: StorageLocation? = nil,
                  expiresAt: Date? = nil, consumed: Bool = false) throws -> InventoryItem {
        let item = spaceStore.insert(InventoryItem.self, in: product.space ?? personal, by: Self.user)
        item.product = product
        item.quantity = consumed ? 0 : quantity
        item.unit = product.defaultUnit
        item.storageLocation = location
        item.expiresAt = expiresAt
        item.isFullyConsumed = consumed
        try context.save()
        return item
    }
}

@MainActor
@Suite("StorageLocationService")
struct StorageLocationServiceTests {
    @Test func createAppendsWithIncreasingSortOrder() throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let fridge = try service.create(in: env.personal, name: "  Fridge ", color: .blue, isFreezer: false)
        let freezer = try service.create(in: env.personal, name: "Freezer", color: nil, isFreezer: true)
        #expect(fridge.name == "Fridge")
        #expect(fridge.color == "blue")
        #expect(fridge.storageColor == .blue)
        #expect(freezer.color == nil)
        #expect(freezer.isFreezer)
        #expect(Int(fridge.sortOrder) == 0)
        #expect(Int(freezer.sortOrder) == 1)
        #expect(fridge.space == env.personal)
        #expect(try service.locations(in: env.personal) == [fridge, freezer])
        #expect(!env.context.hasChanges)
    }

    @Test func blankNameIsRejected() throws {
        let env = try ServiceTestEnvironment()
        #expect(throws: ServiceError.nameRequired) {
            try env.storageService().create(in: env.personal, name: "  ", color: nil, isFreezer: false)
        }
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        #expect(throws: ServiceError.nameRequired) { try env.storageService().rename(fridge, to: "") }
        #expect(fridge.name == "Fridge")
    }

    @Test func updateAndRename() throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let location = try service.create(in: env.personal, name: "Fridge", color: .blue, isFreezer: false)
        try service.update(location, name: "Chest", color: .gray, isFreezer: true)
        #expect(location.name == "Chest" && location.storageColor == .gray && location.isFreezer)
        try service.rename(location, to: " Cellar ")
        #expect(location.name == "Cellar")
        #expect(location.storageColor == .gray)
    }

    @Test func setOrderRewritesSortOrder() throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let a = try service.create(in: env.personal, name: "A", color: nil, isFreezer: false)
        let b = try service.create(in: env.personal, name: "B", color: nil, isFreezer: false)
        let c = try service.create(in: env.personal, name: "C", color: nil, isFreezer: false)
        try service.setOrder([c, a, b])
        #expect(try service.locations(in: env.personal).map(\.name) == ["C", "A", "B"])
        #expect(!env.context.hasChanges)
    }

    @Test func locationsAreScopedToTheSpace() throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let service = env.storageService()
        try service.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        try service.create(in: home, name: "Garage", color: nil, isFreezer: false)
        #expect(try service.locations(in: env.personal).map(\.name) == ["Fridge"])
        #expect(try service.location(named: "fridge", in: env.personal)?.name == "Fridge")
        #expect(try service.location(named: "Garage", in: env.personal) == nil)
    }

    @Test func deleteNullifiesItems() async throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let fridge = try service.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let item = try env.makeItem(milk, quantity: 1, location: fridge)
        #expect(try service.itemCount(in: fridge) == 1)

        try service.delete(fridge)
        #expect(try env.count(StorageLocation.self) == 0)
        #expect(try env.count(InventoryItem.self) == 1)
        #expect(item.storageLocation == nil)
        #expect(item.updatedBy == ServiceTestEnvironment.user)
        #expect(!env.context.hasChanges)
    }

    @Test func itemCountIgnoresConsumedItems() async throws {
        let env = try ServiceTestEnvironment()
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let milk = try await env.makeProduct("Milk")
        try env.makeItem(milk, location: fridge)
        try env.makeItem(milk, location: fridge, consumed: true)
        #expect(try env.storageService().itemCount(in: fridge) == 1)
    }

    @Test func deletionWaitsForCommit() async throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let pantry = try service.create(in: env.personal, name: "Pantry", color: .orange, isFreezer: false)
        let pending = PendingDeletions()

        let undo = try service.deletion(of: pantry, pending: pending)
        #expect(pending.contains(pantry.publicId))
        #expect(try env.count(StorageLocation.self) == 1)
        undo.revert()
        #expect(!pending.contains(pantry.publicId))

        let commit = try service.deletion(of: pantry, pending: pending)
        try commit.commit()
        #expect(try env.count(StorageLocation.self) == 0)
    }

    @Test func readOnlySpaceIsEnforced() throws {
        let env = try ServiceTestEnvironment()
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let readOnly = env.storageService(canEdit: { _ in false })
        #expect(!readOnly.canEdit(env.personal))
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.create(in: env.personal, name: "X", color: nil, isFreezer: false) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.rename(fridge, to: "Y") }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.setOrder([fridge]) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.delete(fridge) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.deletion(of: fridge, pending: PendingDeletions()) }
    }

    @Test func colourNamesAreTranslated() {
        for color in StorageColor.palette {
            for id in ["hu_HU", "en_US", "de_DE"] {
                #expect(CoreLocalization.lookup("storageColor.\(color.rawValue)", locale: Locale(identifier: id)) != nil)
            }
        }
        #expect(StorageColor.palette.count == 8)
    }
}
