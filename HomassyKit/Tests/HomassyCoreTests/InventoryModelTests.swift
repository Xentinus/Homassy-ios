import CoreData
import Foundation
import Observation
import Synchronization
import Testing
@testable import HomassyCore

/// The Inventory grid: "Expiring soon" first, then one section per storage location, then "No location".
/// A card is one product within one section (user choice, 2026-09-24).
@MainActor
@Suite("InventoryModel")
struct InventoryModelTests {
    static let hu = Locale(identifier: "hu_HU")

    func model(_ env: ServiceTestEnvironment, pending: PendingDeletions = PendingDeletions(),
               canEdit: Bool = true) -> InventoryModel {
        let model = InventoryModel(inventory: env.inventoryService(canEdit: { _ in canEdit }),
                                   storage: env.storageService(), space: env.personal, pending: pending, locale: Self.hu)
        model.reload()
        return model
    }

    func locations(_ env: ServiceTestEnvironment) throws -> (fridge: StorageLocation, pantry: StorageLocation, freezer: StorageLocation) {
        let storage = env.storageService()
        return (try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false),
                try storage.create(in: env.personal, name: "Pantry", color: nil, isFreezer: false),
                try storage.create(in: env.personal, name: "Freezer", color: nil, isFreezer: true))
    }

    func names(_ section: InventorySection) -> [String] { section.cards.map(\.name) }

    @Test("Expiring items come first, most urgent first, and are not repeated below")
    func expiringSectionFirst() async throws {
        let env = try ServiceTestEnvironment()
        let (fridge, pantry, _) = try locations(env)
        try env.stock(try await env.makeProduct("Bread"), 1, location: pantry, expiresInDays: -1)
        try env.stock(try await env.makeProduct("Milk", unit: .liter), 1, location: fridge, expiresInDays: 2)
        try env.stock(try await env.makeProduct("Apples", unit: .kilogram), Decimal(string: "1.5")!, expiresInDays: 10)
        try env.stock(try await env.makeProduct("Eggs"), 10, location: fridge, expiresInDays: 20)

        let model = model(env)
        #expect(model.sections.map(\.kind) == [.expiring, .location(fridge.publicId)])
        #expect(names(model.sections[0]) == ["Bread", "Milk", "Apples"])
        #expect(model.sections[0].cards.map(\.expiryLevel) == [.expired, .critical, .soon])
        #expect(model.sections[0].cards[1].expiryText == "Még 2 nap")
        #expect(names(model.sections[1]) == ["Eggs"])
        #expect(model.sections[1].title == "Fridge")
        #expect(!model.isEmpty)
    }

    @Test("One card per product per section, with the stock added up")
    func aggregatesPerProductAndSection() async throws {
        let env = try ServiceTestEnvironment()
        let (fridge, _, freezer) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        try env.stock(eggs, 6, location: fridge, expiresInDays: 30)
        try env.stock(eggs, 6, location: fridge, expiresInDays: 40)
        try env.stock(eggs, 2, location: fridge, expiresInDays: 3)
        let peas = try await env.makeProduct("Peas", unit: .gram)
        try env.stock(peas, 450, location: freezer)
        try env.stock(try await env.makeProduct("Salt", unit: .gram), 500)

        let model = model(env)
        #expect(model.sections.map(\.kind) == [.expiring, .location(fridge.publicId), .location(freezer.publicId), .noLocation])
        #expect(model.sections[0].cards.map(\.stockText) == ["2\u{00A0}db"])
        #expect(model.sections[1].cards.map(\.stockText) == ["2 × 6\u{00A0}db"])
        #expect(model.sections[1].cards.first?.expiryLevel == .ok)
        #expect(model.sections[2].isFreezer && model.sections[2].title == "Freezer")
        #expect(names(model.sections[3]) == ["Salt"] && model.sections[3].title == nil)
    }

    @Test func locationSectionsFollowTheSpaceOrderAndSortByName() async throws {
        let env = try ServiceTestEnvironment()
        let (fridge, pantry, _) = try locations(env)
        try env.storageService().setOrder([pantry, fridge])
        try env.stock(try await env.makeProduct("Rice"), 1, location: pantry)
        try env.stock(try await env.makeProduct("Beans"), 1, location: pantry)
        try env.stock(try await env.makeProduct("Butter"), 1, location: fridge)
        let model = model(env)
        #expect(model.sections.map(\.title) == ["Pantry", "Fridge"])
        #expect(names(model.sections[0]) == ["Beans", "Rice"])
    }

    @Test func consumedItemsAndOtherSpacesAreLeftOut() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk")
        let finished = try env.stock(milk, 1)
        try env.inventoryService().markUsedUp(finished)
        try env.stock(try await env.makeProduct("Soap", in: home), 1)
        let model = model(env)
        #expect(model.sections.isEmpty && model.isEmpty)
    }

    @Test("Items and products whose delete is in its undo window are hidden")
    func pendingDeletionsAreHidden() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let first = try env.stock(eggs, 2)
        try env.stock(eggs, 3)
        let milk = try await env.makeProduct("Milk")
        try env.stock(milk, 1)
        let pending = PendingDeletions()
        let model = model(env, pending: pending)
        #expect(model.sections.first?.cards.map(\.stockText) == ["5\u{00A0}db", "1\u{00A0}db"])

        let itemDeletion = try InventoryActions.delete(first, service: env.inventoryService(), pending: pending)
        #expect(model.sections.first?.cards.map(\.stockText) == ["3\u{00A0}db", "1\u{00A0}db"])
        itemDeletion.revert()
        _ = try env.productService().deletion(of: milk, pending: pending)
        #expect(names(model.sections[0]) == ["Eggs"])
    }

    @Test func canEditFollowsTheSpace() async throws {
        let env = try ServiceTestEnvironment()
        #expect(model(env).canEdit)
        #expect(!model(env, canEdit: false).canEdit)
    }
}

@MainActor
@Suite("InventoryModel observation")
struct InventoryModelObservationTests {
    @Test("Reloading after an edit notifies observers, even though the same objects are fetched")
    func reloadAfterEditNotifies() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 10)
        let model = InventoryModel(inventory: env.inventoryService(), storage: env.storageService(), space: env.personal,
                                   pending: PendingDeletions(), locale: Locale(identifier: "en_US"))
        model.reload()
        let changed = Mutex(false)
        withObservationTracking { _ = model.sections } onChange: { changed.withLock { $0 = true } }
        try env.inventoryService().update(item, quantity: 8, unit: .piece, expiresAt: nil, purchasedAt: nil,
                                          price: nil, currency: nil, storageLocation: nil)
        model.reload()
        #expect(changed.withLock { $0 })
        #expect(model.sections.first?.cards.first?.stockText == "8\u{00A0}pcs")
    }
}
