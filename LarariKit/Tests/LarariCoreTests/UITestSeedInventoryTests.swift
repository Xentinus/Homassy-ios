import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("UITestSeed inventory")
struct UITestSeedInventoryTests {
    @Test func seedFillsTheExpiringAndFridgeSections() async throws {
        let env = try ServiceTestEnvironment()
        let services = ServiceContainer(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user)
        try await UITestSeed.populate(services, in: env.personal)
        let preferences = InventoryPreferences(defaults: UserDefaults(suiteName: "test.seed.\(UUID().uuidString)")!)
        preferences.grouping = .location
        let model = InventoryModel(inventory: services.inventory, storage: services.storageLocations, space: env.personal,
                                   pending: services.pendingDeletions, preferences: preferences)
        model.reload()
        #expect(model.sections.first?.cards.map(\.name) == ["Bread", "Milk", "Apples"])
        #expect(model.sections.dropFirst().first?.cards.map(\.name) == ["Eggs"])
        #expect(model.sections.count == 2)
    }
}
