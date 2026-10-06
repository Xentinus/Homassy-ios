import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Shopping location service")
struct ShoppingLocationServiceTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService

    init() throws {
        stack = try ShoppingTestStack()
        let clock = stack.now
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                            userRecordName: stack.user, now: { clock.date })
    }

    @Test func upsertCreatesAStoreTheFirstTimeItIsPicked() throws {
        let store = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        #expect(store.mapItemIdentifier == "I-SPAR-ASTORIA")
        #expect(store.name == "Spar Astoria")
        #expect(store.latitude == 47.4935)
        #expect(store.longitude == 19.0602)
        #expect(store.lastUsedAt == stack.now.date)
        #expect(store.space == stack.space)
        #expect(!stack.context.hasChanges)
    }

    @Test func upsertMatchesByIdentifierAndRefreshesDetails() throws {
        let first = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        stack.now.advance(seconds: 3600)
        var renamed = StoreSamples.sparAstoria
        renamed.name = "SPAR Astoria (felújítva)"
        renamed.latitude = 47.4936
        let second = try locations.upsert(renamed, in: stack.space)

        #expect(second == first)
        #expect(try stack.count(ShoppingLocation.self) == 1)
        #expect(second.name == "SPAR Astoria (felújítva)")
        #expect(second.latitude == 47.4936)
        #expect(second.lastUsedAt == stack.now.date)
        #expect(second.updatedAt == stack.now.date)
    }

    @Test func upsertIsPerSpace() throws {
        let other = try stack.makeOtherSpace()
        let here = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        let there = try locations.upsert(StoreSamples.sparAstoria, in: other)
        #expect(here != there)
        #expect(there.space == other)
    }

    @Test func upsertRequiresAName() {
        var nameless = StoreSamples.lidlBuda
        nameless.name = "  "
        #expect(throws: ServiceError.nameRequired) { _ = try locations.upsert(nameless, in: stack.space) }
    }

    @Test func writesRejectAReadOnlySpace() throws {
        let spar = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        let readOnly = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                               userRecordName: stack.user, canEdit: { _ in false })
        #expect(throws: ServiceError.readOnlySpace) { _ = try readOnly.upsert(StoreSamples.aldiNyugati, in: stack.space) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.markUsed(spar) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.delete(spar) }
        #expect(try stack.count(ShoppingLocation.self) == 1)
    }

    @Test func recentIsSortedByLastUseAndLimited() throws {
        let spar = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        stack.now.advance(seconds: 10)
        let aldi = try locations.upsert(StoreSamples.aldiNyugati, in: stack.space)
        stack.now.advance(seconds: 10)
        let lidl = try locations.upsert(StoreSamples.lidlBuda, in: stack.space)
        _ = try locations.upsert(StoreSamples.sparAstoria, in: try stack.makeOtherSpace())

        #expect(try locations.recent(in: stack.space) == [lidl, aldi, spar])
        stack.now.advance(seconds: 10)
        try locations.markUsed(spar)
        #expect(try locations.recent(in: stack.space, limit: 2) == [spar, lidl])
    }

    @Test func locationByPublicId() throws {
        let spar = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        #expect(try locations.location(publicId: spar.publicId, in: stack.space) == spar)
        #expect(try locations.location(publicId: spar.publicId, in: try stack.makeOtherSpace()) == nil)
    }

    @Test func deleteClearsReferencesFirst() throws {
        let spar = try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Kenyér", shoppingLocation: spar)
        let milk = try stack.makeProduct("Tej")
        let stock = stack.spaceStore.insert(InventoryItem.self, in: stack.space, by: stack.user)
        stock.product = milk
        stock.quantity = 1
        stock.unit = .liter
        stock.shoppingLocation = spar
        try stack.context.save()

        try locations.delete(spar)

        #expect(try stack.count(ShoppingLocation.self) == 0)
        #expect(item.shoppingLocation == nil)
        #expect(stock.shoppingLocation == nil)
        #expect(try stack.count(ShoppingListItem.self) == 1)
        #expect(try stack.count(InventoryItem.self) == 1)
        #expect(!stack.context.hasChanges)
    }
}
