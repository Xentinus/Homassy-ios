import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Inventory preferences")
struct InventoryPreferencesTests {
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: "test.inventoryPreferences.\(UUID().uuidString)")) }

    @Test func groupingDefaultsToLocationAndIsRemembered() {
        let preferences = InventoryPreferences(defaults: defaults)
        #expect(preferences.grouping == .location)
        preferences.grouping = .expiry
        #expect(InventoryPreferences(defaults: defaults).grouping == .expiry)
    }

    @Test func anUnknownValueFallsBackToLocation() {
        defaults.set("quantity", forKey: "inventory.grouping")
        #expect(InventoryPreferences(defaults: defaults).grouping == .location)
    }
}
