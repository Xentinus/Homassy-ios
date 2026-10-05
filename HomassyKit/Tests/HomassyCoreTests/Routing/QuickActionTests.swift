import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Quick actions")
struct QuickActionTests {
    let en = Locale(identifier: "en_US")
    let space = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let list = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    var info: [String: String] { [QuickAction.spaceIDKey: space.uuidString, QuickAction.listIDKey: list.uuidString] }

    func services(_ env: ServiceTestEnvironment,
                  canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) -> ServiceContainer {
        ServiceContainer(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user,
                         canEdit: canEdit, storeSearch: FakeStoreSearch())
    }

    func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "test.lastList.\(UUID().uuidString)"))
    }

    @Test func typesMapToDestinations() {
        #expect(QuickAction.destination(type: "com.homassy.app.quick.scan", userInfo: [:]) == .scanBarcode)
        #expect(QuickAction.destination(type: "com.homassy.app.quick.expiring", userInfo: [:]) == .inventoryExpiring(spaceID: nil))
        #expect(QuickAction.destination(type: "com.homassy.app.quick.expiring", userInfo: info) == .inventoryExpiring(spaceID: space))
        #expect(QuickAction.destination(type: "com.homassy.app.quick.openList", userInfo: info)
                == .shoppingList(spaceID: space, listID: list))
        #expect(QuickAction.destination(type: "com.homassy.app.quick.addToList", userInfo: info)
                == .addToShoppingList(spaceID: space, listID: list))
    }

    @Test func listActionsWithoutIDsOpenShopping() {
        #expect(QuickAction.destination(type: QuickAction.openList.rawValue, userInfo: [:]) == .shopping(spaceID: nil))
        #expect(QuickAction.destination(type: QuickAction.addToList.rawValue,
                                        userInfo: [QuickAction.spaceIDKey: space.uuidString]) == .shopping(spaceID: space))
    }

    @Test func unknownTypeIsIgnored() {
        #expect(QuickAction.destination(type: "com.example.other", userInfo: [:]) == nil)
    }

    @Test func menuWithALastListAndExpiringItems() {
        let items = QuickActionPlanner.items(lastList: ShoppingListReference(spaceID: space, listID: list),
                                             listName: "Weekly", expiringCount: 3, locale: en)
        #expect(items.map(\.type) == [QuickAction.scanBarcode, .addToList, .openList, .expiringSoon].map(\.rawValue))
        #expect(items.map(\.title) == ["Scan Barcode", "Add to List", "Weekly", "Expiring Soon"])
        #expect(items.map(\.subtitle) == [nil, "Weekly", "Shopping list", "3 items"])
        #expect(items.map(\.systemImage) == ["barcode.viewfinder", "cart.badge.plus", "list.bullet", "clock.badge.exclamationmark"])
        #expect(items[1].userInfo == info)
        #expect(items[2].userInfo == info)
        #expect(items.count <= QuickActionPlanner.maxItems)
    }

    @Test func menuWithoutAListOrExpiringItems() {
        let items = QuickActionPlanner.items(lastList: nil, listName: "", expiringCount: 0, locale: en)
        #expect(items.map(\.type) == [QuickAction.scanBarcode.rawValue, QuickAction.expiringSoon.rawValue])
        #expect(items[1].subtitle == nil)
        #expect(QuickActionPlanner.items(lastList: nil, listName: "", expiringCount: 1, locale: en)[1].subtitle == "1 item")
    }

    @Test func hungarianAndGermanTitles() {
        let hu = QuickActionPlanner.items(lastList: ShoppingListReference(spaceID: space, listID: list),
                                          listName: "Heti", expiringCount: 3, locale: Locale(identifier: "hu_HU"))
        #expect(hu.map(\.title) == ["Vonalkód beolvasása", "Hozzáadás a listához", "Heti", "Hamarosan lejár"])
        #expect(hu.map(\.subtitle) == [nil, "Heti", "Bevásárlólista", "3 tétel"])
        let de = QuickActionPlanner.items(lastList: nil, listName: "", expiringCount: 2, locale: Locale(identifier: "de_DE"))
        #expect(de.map(\.title) == ["Barcode scannen", "Läuft bald ab"])
        #expect(de[1].subtitle == "2 Artikel")
    }

    @Test func theLastListIsGlobalAcrossSpaces() throws {
        let store = LastUsedShoppingList(defaults: try defaults())
        let home = UUID(), office = UUID(), weekly = UUID(), party = UUID()
        #expect(store.lastReference == nil)
        store.record(weekly, for: home)
        #expect(store.lastReference == ShoppingListReference(spaceID: home, listID: weekly))
        store.record(party, for: office)
        #expect(store.lastReference == ShoppingListReference(spaceID: office, listID: party))
        #expect(store.listID(for: home) == weekly)                  // the per-space memory is unchanged
    }

    @Test func menuFromTheStoreDropsADeletedList() throws {
        let env = try ServiceTestEnvironment()
        let services = services(env)
        let weekly = try services.shopping.createList(name: "Weekly", in: env.personal)
        let lastUsed = LastUsedShoppingList(defaults: try defaults())
        lastUsed.record(weekly.publicId, for: env.personal.publicId)

        let before = QuickActionPlanner.items(services: services, lastUsed: lastUsed, now: .now, calendar: .current, locale: en)
        #expect(before.map(\.title) == ["Scan Barcode", "Add to List", "Weekly", "Expiring Soon"])

        try services.shopping.deleteList(weekly)
        let after = QuickActionPlanner.items(services: services, lastUsed: lastUsed, now: .now, calendar: .current, locale: en)
        #expect(after.map(\.type) == [QuickAction.scanBarcode.rawValue, QuickAction.expiringSoon.rawValue])
    }

    @Test func expiringCountIsTheBadgeCount() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        try env.stock(milk, 1, expiresInDays: 1)
        try env.stock(milk, 1, expiresInDays: 40)
        let items = QuickActionPlanner.items(services: services(env), lastUsed: LastUsedShoppingList(defaults: try defaults()),
                                             now: ServiceTestEnvironment.fixedNow, calendar: ServiceTestEnvironment.budapest,
                                             locale: en)
        #expect(items.last?.subtitle == "1 item")
    }

    @Test func validatedDestinations() throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let services = services(env, canEdit: { $0.kind == .personal })
        let own = try services.shopping.createList(name: "Weekly", in: env.personal)
        let editor = ShoppingService(spaceStore: env.spaceStore, context: env.context,
                                     userRecordName: ServiceTestEnvironment.user)
        let readOnly = try editor.createList(name: "Shared", in: home)
        let personalID = env.personal.publicId

        #expect(services.validated(.shoppingList(spaceID: personalID, listID: UUID())) == .shopping(spaceID: personalID))
        #expect(services.validated(.addToShoppingList(spaceID: personalID, listID: UUID())) == .shopping(spaceID: personalID))
        #expect(services.validated(.shoppingList(spaceID: UUID(), listID: own.publicId)) == .shopping(spaceID: nil))
        #expect(services.validated(.shopping(spaceID: UUID())) == .shopping(spaceID: nil))
        #expect(services.validated(.shoppingList(spaceID: personalID, listID: own.publicId))
                == .shoppingList(spaceID: personalID, listID: own.publicId))
        #expect(services.validated(.addToShoppingList(spaceID: personalID, listID: own.publicId))
                == .addToShoppingList(spaceID: personalID, listID: own.publicId))
        #expect(services.validated(.addToShoppingList(spaceID: home.publicId, listID: readOnly.publicId))
                == .shoppingList(spaceID: home.publicId, listID: readOnly.publicId))
        #expect(services.validated(.scanBarcode) == .scanBarcode)
        #expect(services.validated(.inventory(spaceID: nil)) == .inventory(spaceID: nil))
        #expect(services.validated(.inventory(spaceID: UUID())) == .inventory(spaceID: nil))
        #expect(services.validated(.inventoryExpiring(spaceID: nil)) == .inventoryExpiring(spaceID: nil))
        #expect(services.validated(.inventoryExpiring(spaceID: UUID())) == .inventoryExpiring(spaceID: nil))
    }
}
