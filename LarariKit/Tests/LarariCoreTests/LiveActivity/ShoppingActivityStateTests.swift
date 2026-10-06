import CoreData
import Foundation
import LarariShared
import Testing
@testable import LarariCore

@MainActor
@Suite("ShoppingActivityState")
struct ShoppingActivityStateTests {
    let stack: ShoppingTestStack
    let hu = Locale(identifier: "hu_HU")
    init() throws { stack = try ShoppingTestStack() }

    func open(_ scope: ShoppingActivityScope, in space: Space? = nil) throws -> [ShoppingListItem] {
        try ShoppingActivityState.openItems(scope: scope, in: space ?? stack.space, service: stack.service,
                                            pending: stack.pending)
    }

    @Test func aStoreScopeTakesItsItemsFromEveryListInListOrder() throws {
        let spar = try stack.makeStore("Spar Budaörs")
        let auchan = try stack.makeStore("Auchan Budaörs")
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: stack.space)
        try stack.service.addItem(to: weekly, customName: "Kenyér", shoppingLocation: spar)
        try stack.service.addItem(to: weekly, customName: "Mosópor", shoppingLocation: auchan)
        try stack.service.addItem(to: weekly, customName: "Szappan")                       // no store
        try stack.service.addItem(to: party, customName: "Chips", shoppingLocation: spar)
        #expect(try open(.store(spar.publicId)).map(ShoppingService.displayName(of:)) == ["Kenyér", "Chips"])
    }

    @Test func boughtAndUndoPendingItemsAreLeftOut() throws {
        let spar = try stack.makeStore("Spar")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let a = try stack.service.addItem(to: list, customName: "Tej", shoppingLocation: spar)
        let b = try stack.service.addItem(to: list, customName: "Vaj", shoppingLocation: spar)
        try stack.service.addItem(to: list, customName: "Alma", shoppingLocation: spar)
        try stack.service.togglePurchased(a)                   // an old-style bought row stays hidden
        stack.pending.hide(b.publicId)                         // in an undo window
        #expect(try open(.store(spar.publicId)).map(ShoppingService.displayName(of:)) == ["Alma"])
    }

    @Test func aChainScopeTakesEveryStoreOfTheChainInTheSpaceOnly() throws {
        let other = try stack.makeOtherSpace()
        let budaors = try stack.makeStore("Spar Budaörs")
        let budakeszi = try stack.makeStore("SPAR Budakeszi")
        let partner = try stack.makeStore("Spar Partner Törökbálint")                     // another chain key
        let elsewhere = try stack.makeStore("Spar Budaörs", in: other)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let otherList = try stack.service.createList(name: "Heti", in: other)
        try stack.service.addItem(to: list, customName: "Tej", shoppingLocation: budaors)
        try stack.service.addItem(to: list, customName: "Vaj", shoppingLocation: budakeszi)
        try stack.service.addItem(to: list, customName: "Liszt", shoppingLocation: partner)
        try stack.service.addItem(to: otherList, customName: "Só", shoppingLocation: elsewhere)
        #expect(try open(.chain("spar")).map(ShoppingService.displayName(of:)) == ["Tej", "Vaj"])
    }

    @Test func theSameProductInTheSameUnitIsOneRowWithTheQuantitiesAdded() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: stack.space)
        let first = try stack.service.addItem(to: weekly, product: milk, quantity: 2, shoppingLocation: spar)
        try stack.service.addItem(to: weekly, customName: "Kenyér", shoppingLocation: spar)
        let second = try stack.service.addItem(to: party, product: milk, quantity: 1, shoppingLocation: spar)
        try stack.service.addItem(to: party, product: milk, quantity: 6, unit: .piece, shoppingLocation: spar)
        try stack.service.addItem(to: party, customName: "Kenyér", shoppingLocation: spar)   // name-only: never merged

        let rows = ShoppingActivityState.rows(for: try open(.store(spar.publicId)), locale: hu)

        #expect(rows.map(\.name) == ["Tej", "Kenyér", "Tej", "Kenyér"])
        #expect(rows[0].quantity == Quantity.format(3, unit: .liter, locale: hu))
        #expect(rows[0].itemIDs == [first.publicId, second.publicId])
        #expect(rows[0].id == "p:\(milk.publicId.uuidString):liter")
        #expect(rows[2].quantity == Quantity.format(6, unit: .piece, locale: hu))
        #expect(Set(rows.map(\.id)).count == 4)
    }

    @Test func theTitleIsTheStoreOrTheChainAndNilWhenTheStoreIsGone() throws {
        let spar = try stack.makeStore("Spar Budaörs")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.addItem(to: list, customName: "Tej", shoppingLocation: spar)
        let items = try open(.chain("spar"))
        let locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                                userRecordName: stack.user)
        #expect(ShoppingActivityState.title(scope: .store(spar.publicId), in: stack.space, items: [],
                                            locations: locations) == "Spar Budaörs")
        #expect(ShoppingActivityState.title(scope: .chain("spar"), in: stack.space, items: items,
                                            locations: locations) == "Spar")
        #expect(ShoppingActivityState.title(scope: .chain("spar"), in: stack.space, items: [],
                                            locations: locations) == nil)
        let id = spar.publicId
        stack.context.delete(spar)
        try stack.context.save()
        #expect(ShoppingActivityState.title(scope: .store(id), in: stack.space, items: [], locations: locations) == nil)
    }

    @Test func severalNearbyStoresShareOneScopeAndTitle() throws {
        let spar = try stack.makeStore("Spar Budaörs")
        let dm = try stack.makeStore("dm Budaörs")
        let auchan = try stack.makeStore("Auchan Budaörs")
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: stack.space)
        try stack.service.addItem(to: weekly, customName: "Tej", shoppingLocation: spar)
        try stack.service.addItem(to: weekly, customName: "Mosópor", shoppingLocation: auchan)
        try stack.service.addItem(to: party, customName: "Fogkrém", shoppingLocation: dm)
        let scope = ShoppingActivityScope.stores([spar.publicId, dm.publicId].sorted { $0.uuidString < $1.uuidString })
        let locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                                userRecordName: stack.user)

        #expect(try open(scope).map(ShoppingService.displayName(of:)) == ["Tej", "Fogkrém"])
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: [], locations: locations, locale: hu)
                == "2 közeli bolt")
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: [], locations: locations,
                                            locale: Locale(identifier: "en_US")) == "2 nearby stores")
        let items = try open(scope)
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: items, locations: locations, locale: hu)
                == "2 közeli bolt")
        let sparOnly = items.filter { $0.shoppingLocation?.publicId == spar.publicId }
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: sparOnly, locations: locations,
                                            locale: hu) == "Spar Budaörs")
        stack.context.delete(dm)
        try stack.context.save()
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: [], locations: locations, locale: hu)
                == "Spar Budaörs")
        stack.context.delete(spar)
        try stack.context.save()
        #expect(ShoppingActivityState.title(scope: scope, in: stack.space, items: [], locations: locations, locale: hu) == nil)
    }

    @Test func contentShowsThreeNextRowsTheCountsAndTheListCount() throws {
        let spar = try stack.makeStore("Spar")
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: stack.space)
        for name in ["A", "B", "C"] { try stack.service.addItem(to: weekly, customName: name, shoppingLocation: spar) }
        for name in ["D", "E"] { try stack.service.addItem(to: party, customName: name, shoppingLocation: spar) }
        let items = try open(.store(spar.publicId))
        let content = ShoppingActivityState.content(
            title: "Spar", spaceName: "Otthon", listCount: ShoppingActivityState.listCount(of: items),
            rows: ShoppingActivityState.rows(for: items, locale: hu), doneCount: 2, canTick: true)
        #expect(content.nextItems.map(\.name) == ["A", "B", "C"])
        #expect(content.remainingCount == 5)
        #expect(content.doneCount == 2)
        #expect(content.totalCount == 7)
        #expect(content.listCount == 2)
        #expect(content.title == "Spar")
        #expect(content.spaceName == "Otthon")
        #expect(content.canTick)
        #expect(!content.isFinished)
    }

    @Test func longNamesAreShortenedToFortyCharacters() {
        let short = ShoppingActivityState.truncated(String(repeating: "x", count: 60))
        #expect(short.count == ShoppingActivityState.maxNameLength)
        #expect(short.hasSuffix("…"))
        #expect(ShoppingActivityState.truncated("Tej") == "Tej")
    }

    @Test func progressCountsRowsThatLeftAndForgetsRowsThatCameBack() {
        var progress = ShoppingActivityProgress(openKeys: ["a", "b", "c"], carriedDone: 1)
        progress.observe(openKeys: ["a", "c"])            // b bought
        #expect(progress.doneCount == 2)
        progress.observe(openKeys: ["a", "c", "d"])       // d added: not done
        #expect(progress.doneCount == 2)
        progress.observe(openKeys: ["a", "b", "c", "d"])  // b back (undo in the app)
        #expect(progress.doneCount == 1)
        progress.observe(openKeys: [])
        #expect(progress.doneCount == 5)
    }
}
