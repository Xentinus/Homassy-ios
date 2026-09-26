import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Store menu")
struct StoreMenuModelTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService

    init() throws {
        stack = try ShoppingTestStack()
        let clock = stack.now
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                            userRecordName: stack.user, now: { clock.date })
    }

    @discardableResult
    private func store(_ name: String, usedHoursAgo hours: Double, in space: Space? = nil) throws -> ShoppingLocation {
        let store = try stack.makeStore(name, in: space)
        store.lastUsedAt = stack.now.date.addingTimeInterval(-hours * 3600)
        try stack.context.save()
        return store
    }

    private func bought(_ product: Product, at store: ShoppingLocation, daysAgo: Double) throws {
        try stack.inventory.recordPurchase(product: product, quantity: 1, unit: .piece, price: 100, currency: "HUF",
                                           store: store, purchasedAt: stack.now.date.addingTimeInterval(-daysAgo * 86_400))
    }

    private func menu(preset: ShoppingLocation? = nil, product: Product? = nil) -> StoreMenuModel {
        StoreMenuModel(preset: preset, product: product, space: stack.space, locations: locations)
    }

    @Test func productStoresComeFirstThenTheSpaceRecents() throws {
        let milk = try stack.makeProduct("Tej")
        try store("Piac", usedHoursAgo: 1)
        try store("Pékség", usedHoursAgo: 2)
        let sarki = try store("Sarki bolt", usedHoursAgo: 30)
        let nagy = try store("Nagy áruház", usedHoursAgo: 40)
        try bought(milk, at: nagy, daysAgo: 5)
        try bought(milk, at: sarki, daysAgo: 1)
        try bought(milk, at: sarki, daysAgo: 3)
        #expect(try locations.recentStores(for: milk, in: stack.space).map(\.name)
                == ["Sarki bolt", "Nagy áruház", "Piac", "Pékség"])
        #expect(try locations.recentStores(for: nil, in: stack.space).map(\.name)
                == ["Piac", "Pékség", "Sarki bolt", "Nagy áruház"])
    }

    @Test func atMostFiveAndOnlyThisSpace() throws {
        let milk = try stack.makeProduct("Tej")
        let stores = try (1...7).map { try store("Bolt \($0)", usedHoursAgo: Double($0)) }
        try bought(milk, at: stores[6], daysAgo: 1)
        try store("Idegen", usedHoursAgo: 0, in: try stack.makeOtherSpace())
        #expect(try locations.recentStores(for: milk, in: stack.space).map(\.name)
                == ["Bolt 7", "Bolt 1", "Bolt 2", "Bolt 3", "Bolt 4"])
    }

    @Test func menuListsTheRecentStoresForTheProduct() throws {
        let milk = try stack.makeProduct("Tej")
        try store("Piac", usedHoursAgo: 1)
        let sarki = try store("Sarki bolt", usedHoursAgo: 30)
        try bought(milk, at: sarki, daysAgo: 1)
        let model = menu()
        #expect(model.options.map(\.name) == ["Piac", "Sarki bolt"])
        model.setProduct(milk)
        #expect(model.options.map(\.name) == ["Sarki bolt", "Piac"])
    }

    @Test func anUntouchedMenuTakesTheSuggestion() throws {
        let model = menu()
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(model.name == "Aldi Nyugati" && model.suggestedDistance == 40 && !model.offersSuggestion)
        let resolved = try #require(try model.resolve())
        #expect(resolved.mapItemIdentifier == StoreSamples.aldiNyugati.mapItemIdentifier)
    }

    @Test func noStoreBeatsALaterSuggestionUntilTheSuggestionIsPicked() {
        let model = menu()
        model.choose(nil)
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(model.name == nil)
        #expect(model.offersSuggestion)
        model.chooseSuggestion()
        #expect(model.name == "Aldi Nyugati" && model.suggestedDistance == 40 && !model.offersSuggestion)
    }

    @Test func pickingARecentStoreOrAnotherStore() throws {
        let piac = try store("Piac", usedHoursAgo: 1)
        let model = menu()
        model.choose(piac.publicId)
        #expect(model.selectedStoreID == piac.publicId && model.name == "Piac")
        let later = try stack.makeStore("Új bolt")
        model.setStore(later)
        #expect(model.options.first?.name == "Új bolt")
        #expect(model.selectedStoreID == later.publicId)
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(model.name == "Új bolt" && model.offersSuggestion)
    }

    @Test func aSavedSuggestionThatIsAlreadyChosenIsNotOfferedTwice() throws {
        let piac = try store("Piac", usedHoursAgo: 1)
        let model = menu(preset: piac)
        model.applySuggestion(.saved(id: piac.publicId, name: "Piac", distance: 20))
        #expect(!model.offersSuggestion)
        #expect(model.name == "Piac" && model.suggestedDistance == nil)
    }
}
