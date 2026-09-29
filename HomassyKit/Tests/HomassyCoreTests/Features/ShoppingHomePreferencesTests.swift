import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping home preferences")
struct ShoppingHomePreferencesTests {
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: "test.shoppingHome.\(UUID().uuidString)")) }

    @Test func theFilterIsPerSpaceAndCanBeCleared() {
        let preferences = ShoppingHomePreferences(defaults: defaults)
        let home = UUID(), office = UUID(), list = UUID()
        #expect(preferences.filter(for: home) == nil)
        preferences.setFilter(list, for: home)
        #expect(ShoppingHomePreferences(defaults: defaults).filter(for: home) == list)
        #expect(preferences.filter(for: office) == nil)
        preferences.setFilter(nil, for: home)
        #expect(preferences.filter(for: home) == nil)
    }

    @Test func groupingDefaultsToListAndIsRemembered() {
        let preferences = ShoppingHomePreferences(defaults: defaults)
        #expect(preferences.grouping == .list)
        preferences.grouping = .store
        #expect(ShoppingHomePreferences(defaults: defaults).grouping == .store)
    }
}

@MainActor
@Suite("Last used shopping list")
struct LastUsedShoppingListTests {
    @Test func oneListPerSpace() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.lastList.\(UUID().uuidString)"))
        let lastUsed = LastUsedShoppingList(defaults: defaults)
        let home = UUID(), office = UUID(), weekly = UUID(), party = UUID()
        #expect(lastUsed.listID(for: home) == nil)
        lastUsed.record(weekly, for: home)
        lastUsed.record(party, for: office)
        #expect(LastUsedShoppingList(defaults: defaults).listID(for: home) == weekly)
        #expect(lastUsed.listID(for: office) == party)
    }
}
