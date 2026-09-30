import CoreData
import Foundation
import HomassyShared
import Testing
@testable import HomassyCore

@MainActor
@Suite("ShoppingActivityTrigger")
struct ShoppingActivityTriggerTests {
    // Budaörs area. One degree of latitude is about 111 195 m.
    let here = Coordinate(latitude: 47.4600, longitude: 18.9500)
    func north(_ metres: Double) -> Coordinate {
        Coordinate(latitude: here.latitude + metres / 111_195, longitude: here.longitude)
    }
    let home = UUID(), family = UUID()

    func store(_ space: UUID, chain: String = "spar", at center: Coordinate?, waiting: Int = 2) -> WaitingStore {
        WaitingStore(storeID: UUID(), spaceID: space, chainKey: chain, center: center, waiting: waiting)
    }

    @Test func aSavedStoreWithin150MetresWins() {
        let near = store(home, at: north(80))
        let far = store(home, at: north(400))
        let target = ShoppingActivityTrigger.target(position: here, stores: [far, near], branches: [],
                                                    preferredSpaceID: nil)
        #expect(target == ShoppingActivityTarget(spaceID: home, scope: .store(near.storeID), center: north(80)))
    }

    @Test func storesWithoutWaitingItemsOrPositionDoNotCount() {
        let empty = store(home, at: north(20), waiting: 0)
        let unknown = store(home, at: nil)
        #expect(ShoppingActivityTrigger.target(position: here, stores: [empty, unknown], branches: [],
                                               preferredSpaceID: nil) == nil)
    }

    @Test func theSamePlaceInTwoHouseholdsPrefersTheSelectedOneThenTheOneWithMoreItems() {
        let mine = store(home, at: north(30), waiting: 1)
        let theirs = store(family, at: north(40), waiting: 5)
        #expect(ShoppingActivityTrigger.target(position: here, stores: [mine, theirs], branches: [],
                                               preferredSpaceID: home)?.spaceID == home)
        #expect(ShoppingActivityTrigger.target(position: here, stores: [mine, theirs], branches: [],
                                               preferredSpaceID: nil)?.spaceID == family)
    }

    @Test func atAnUnsavedBranchTheChainOfTheHouseholdWithMostItemsStarts() {
        let saved = store(home, at: north(3_000), waiting: 3)                      // Spar Budaörs, far away
        let theirs = store(family, at: north(5_000), waiting: 1)
        let branch = ChainBranch(chainKey: "spar", center: north(60))              // Spar Budakeszi, here
        let target = ShoppingActivityTrigger.target(position: here, stores: [saved, theirs], branches: [branch],
                                                    preferredSpaceID: nil)
        #expect(target == ShoppingActivityTarget(spaceID: home, scope: .chain("spar"), center: north(60)))
    }

    @Test func aBranchOfAChainWithoutItemsOrTooFarStartsNothing() {
        let saved = store(home, chain: "spar", at: north(3_000))
        #expect(ShoppingActivityTrigger.target(position: here, stores: [saved],
                                               branches: [ChainBranch(chainKey: "auchan", center: north(10))],
                                               preferredSpaceID: nil) == nil)
        #expect(ShoppingActivityTrigger.target(position: here, stores: [saved],
                                               branches: [ChainBranch(chainKey: "spar", center: north(200))],
                                               preferredSpaceID: nil) == nil)
    }

    @Test func aSavedStoreBeatsANearerBranch() {
        let saved = store(home, chain: "auchan", at: north(140))
        let branch = ChainBranch(chainKey: "auchan", center: north(10))
        #expect(ShoppingActivityTrigger.target(position: here, stores: [saved], branches: [branch],
                                               preferredSpaceID: nil)?.scope == .store(saved.storeID))
    }

    @Test func waitingStoresCountOpenItemsPerStoreAcrossSpaces() throws {
        let stack = try ShoppingTestStack()
        let other = try stack.makeOtherSpace()
        let spar = try stack.makeStore("Spar Budaörs")
        spar.latitude = 47.46
        spar.longitude = 18.95
        let theirs = try stack.makeStore("Spar Budaörs", in: other)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let otherList = try stack.service.createList(name: "Heti", in: other)
        try stack.service.addItem(to: list, customName: "Tej", shoppingLocation: spar)
        let hidden = try stack.service.addItem(to: list, customName: "Vaj", shoppingLocation: spar)
        try stack.service.addItem(to: list, customName: "Só")
        try stack.service.addItem(to: otherList, customName: "Liszt", shoppingLocation: theirs)
        stack.pending.hide(hidden.publicId)

        let stores = try ShoppingActivityTrigger.waitingStores(in: stack.context, pending: stack.pending)

        #expect(stores.count == 2)
        #expect(stores.map(\.chainKey) == ["spar", "spar"])
        let mine = try #require(stores.first { $0.spaceID == stack.space.publicId })
        #expect(mine.storeID == spar.publicId)
        #expect(mine.waiting == 1)
        #expect(mine.center == Coordinate(latitude: 47.46, longitude: 18.95))
        #expect(stores.first { $0.spaceID == other.publicId }?.center == nil)
    }

    @Test func theChainKeyComesBackFromAReminderIdentifier() {
        #expect(StoreReminderPlanner.chainKey(fromIdentifier: "store-spar-0") == "spar")
        #expect(StoreReminderPlanner.chainKey(fromIdentifier: "store-tesco_expressz-12") == "tesco expressz")
        #expect(StoreReminderPlanner.chainKey(fromIdentifier: "preview-store-spar-0") == nil)
        #expect(StoreReminderPlanner.chainKey(fromIdentifier: "daily-2026-09-30") == nil)
        #expect(StoreReminderPlanner.chainKey(fromIdentifier: "store-") == nil)
    }
}
