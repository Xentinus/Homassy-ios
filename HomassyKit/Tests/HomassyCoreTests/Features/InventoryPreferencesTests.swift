import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Inventory preferences")
struct InventoryPreferencesTests {
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: "test.inventoryPreferences.\(UUID().uuidString)")) }

    @Test func groupingDefaultsToNameAndIsRemembered() {
        let preferences = InventoryPreferences(defaults: defaults)
        #expect(preferences.grouping == .name)
        preferences.grouping = .expiry
        #expect(InventoryPreferences(defaults: defaults).grouping == .expiry)
    }

    @Test func anUnknownValueFallsBackToName() {
        defaults.set("quantity", forKey: "inventory.grouping")
        #expect(InventoryPreferences(defaults: defaults).grouping == .name)
    }
}
