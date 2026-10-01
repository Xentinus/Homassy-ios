import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("ProductDetailModel")
struct ProductDetailModelTests {
    static let en = Locale(identifier: "en_US")

    func model(_ env: ServiceTestEnvironment, _ product: Product, pending: PendingDeletions = PendingDeletions(),
               canEdit: Bool = true) -> ProductDetailModel {
        let editable: @MainActor (Space) -> Bool = { _ in canEdit }
        let model = ProductDetailModel(product: product,
                                       products: env.productService(canEdit: editable),
                                       inventory: env.inventoryService(canEdit: editable),
                                       storageLocations: env.storageService(canEdit: editable),
                                       pending: pending, userRecordName: ServiceTestEnvironment.user, locale: Self.en)
        model.reload()
        return model
    }

    func locations(_ env: ServiceTestEnvironment) throws -> (pantry: StorageLocation, fridge: StorageLocation, freezer: StorageLocation) {
        let storage = env.storageService()
        return (try storage.create(in: env.personal, name: "Pantry", color: nil, isFreezer: false),
                try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false),
                try storage.create(in: env.personal, name: "Freezer", color: nil, isFreezer: true))
    }

    // MARK: Reading

    @Test func headerFields() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs", brand: "Farm", category: "Dairy", barcode: "5990000000001")
        let fields = try #require(model(env, eggs).fields)
        #expect(fields.name == "Eggs" && fields.brand == "Farm" && fields.category == "Dairy")
        #expect(fields.barcode == "5990000000001" && !fields.isFavorite && fields.url == nil)
        #expect(fields.unitName == MeasureUnit.piece.name(for: 1, locale: Self.en))
    }

    @Test("Stock is one list: soonest expiry first, no expiry last, then the older purchase")
    func stockLots() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge, freezer) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        try env.stock(eggs, 10, location: fridge, expiresInDays: 20)
        try env.stock(eggs, 4, location: fridge, expiresInDays: 2)
        try env.stock(eggs, 2, location: pantry, expiresInDays: 9)
        try env.stock(eggs, 1)
        try env.stock(eggs, 6, location: freezer, expiresInDays: 90)

        let model = model(env, eggs)
        #expect(model.stock.map(\.card.quantityText) == ["4\u{00A0}pcs", "2\u{00A0}pcs", "10\u{00A0}pcs", "6\u{00A0}pcs", "1\u{00A0}pc"])
        #expect(model.stock.map(\.locationName) == ["Fridge", "Pantry", "Fridge", "Freezer", nil])
        #expect(model.stock.map(\.isFreezer) == [false, false, false, true, false])
        #expect(model.stockTotalText == "23\u{00A0}pcs")
        #expect(model.stockCount == 5)
        #expect(model.stock[0].card.level == .critical && model.stock[0].card.expiryText == "2 days left")
    }

    @Test func sameExpiryShowsTheOlderPurchaseFirst() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let service = env.inventoryService()
        for (quantity, purchased) in [(Decimal(1), -1), (Decimal(2), -5)] {
            try service.addStock(product: milk, quantity: quantity, unit: .liter, expiresAt: env.day(4),
                                 purchasedAt: env.day(purchased), price: nil, currency: nil, storageLocation: nil,
                                 shoppingLocation: nil)
        }
        #expect(model(env, milk).stock.map(\.card.quantity) == [2, 1])
    }

    @Test func pendingDeleteHidesTheLot() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3)
        try env.stock(eggs, 5)
        let pending = PendingDeletions()
        let model = model(env, eggs, pending: pending)
        _ = model.deleteItem(item.publicId)
        #expect(model.stock.map(\.card.quantity) == [5])
        #expect(model.stockTotalText == "5\u{00A0}pcs")
    }

    @Test func noStockHasNoTotal() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let model = model(env, eggs)
        #expect(model.stock.isEmpty && model.stockTotalText == nil)
    }

    @Test("Recent history is the newest three; months group the rest")
    func historyMonths() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        func service(at date: Date) -> InventoryService {
            InventoryService(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user,
                             canEdit: { _ in true }, calendar: ServiceTestEnvironment.budapest, defaultCurrency: "HUF",
                             now: { date })
        }
        for offset in [-40, -35, -2, -1, 0] {
            try service(at: env.day(offset)).addStock(product: eggs, quantity: 1, unit: .piece, expiresAt: nil,
                                                      purchasedAt: nil, price: nil, currency: nil,
                                                      storageLocation: nil, shoppingLocation: nil)
        }

        let model = model(env, eggs)
        #expect(model.history.count == 5)
        #expect(model.recentHistory.map(\.id) == Array(model.history.prefix(3)).map(\.id))
        #expect(model.historyByMonth.map(\.title) == ["September 2026", "August 2026"])
        #expect(model.historyByMonth.map(\.id) == ["2026-09", "2026-08"])
        #expect(model.historyByMonth.map(\.rows.count) == [3, 2])
    }

    @Test("Price trend: six months in the average's currency and unit, oldest first")
    func priceTrendPoints() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let service = env.inventoryService()
        func buy(_ quantity: Decimal, _ unit: MeasureUnit, _ price: Decimal, _ currency: String, day: Int) throws {
            try service.addStock(product: milk, quantity: quantity, unit: unit, expiresAt: nil, purchasedAt: env.day(day),
                                 price: price, currency: currency, storageLocation: nil, shoppingLocation: nil)
        }
        try buy(1, .liter, 5, "EUR", day: -270)                      // older than six months
        try buy(1, .liter, Decimal(string: "3.2")!, "EUR", day: -10)
        try buy(2, .liter, 7, "EUR", day: -1)
        try buy(1, .liter, 4, "USD", day: -3)                        // other currency

        let model = model(env, milk)
        let trend = try #require(model.priceTrend)
        #expect(trend.currency == "EUR" && trend.unit == .liter)
        #expect(trend.points.map(\.unitPrice) == [Decimal(string: "3.2")!, Decimal(string: "3.5")!])
        #expect(model.latestPrice?.price == 7)
    }

    @Test func noPricesMeansNoTrend() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        try env.stock(milk, 1)
        let model = model(env, milk)
        #expect(model.priceTrend == nil && model.latestPrice == nil)
    }

    @Test("Price trend: average unit price and each store's latest, including used-up stock")
    func priceTrend() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let service = env.inventoryService()
        let old = try service.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: env.day(-10),
                                       price: Decimal(string: "3.2")!, currency: "EUR", storageLocation: nil, shoppingLocation: nil)
        try service.markUsedUp(old)
        try service.addStock(product: milk, quantity: 2, unit: .liter, expiresAt: nil, purchasedAt: env.day(-1),
                             price: 7, currency: "EUR", storageLocation: nil, shoppingLocation: nil)
        try env.stock(milk, 1)                                                        // no price

        let model = model(env, milk)
        #expect(model.priceEntries.map(\.price) == [7, Decimal(string: "3.2")!])
        let average = try #require(model.priceSummary.average)
        #expect(model.unitPriceText(average.unitPrice, currency: average.currency, unit: average.unit) == "€3.35 / l")
        let line = try #require(model.priceSummary.stores.first)
        #expect(line.key == PriceHistory.noStoreKey)
        #expect(line.count == 2)
        #expect(model.unitPriceText(line.latest) == "€3.50 / l")
        #expect(model.quantityText(line.latest) == "2\u{00A0}l")
        #expect(model.chartEntries(storeKey: line.key).map(\.date) == [env.day(-10), env.day(-1)])
    }

    @Test("History lists every event newest first, with who did it")
    func history() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge, _) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        try env.inventoryService(user: ServiceTestEnvironment.otherUser).move(item, quantity: 4, to: fridge)
        let member = env.spaceStore.insert(Member.self, in: env.personal, by: ServiceTestEnvironment.user)
        member.space = env.personal
        member.userRecordName = ServiceTestEnvironment.otherUser
        member.displayName = "Anna"
        member.colorSeed = "anna-seed"
        try env.context.save()

        let rows = model(env, eggs).history
        #expect(rows.map(\.kind) == [.moved, .added])
        #expect(rows[0].quantityText == "4\u{00A0}pcs")
        #expect(rows[0].fromLocation == "Pantry" && rows[0].toLocation == "Fridge")
        #expect(rows[0].actorName == "Anna" && !rows[0].isCurrentUser && rows[0].actorSeed == "anna-seed")
        #expect(rows[1].isCurrentUser && rows[1].actorName == nil && rows[1].actorSeed == ServiceTestEnvironment.user)
    }

    @Test func goneProductClearsEverything() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        try env.stock(milk, 1)
        let model = model(env, milk)
        try env.productService().delete(milk)
        model.reload()
        #expect(model.fields == nil)
        #expect(model.stock.isEmpty && model.history.isEmpty && model.priceEntries.isEmpty)
    }

    // MARK: Actions

    @Test func toggleFavoriteSaves() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let model = model(env, milk)
        model.toggleFavorite()
        #expect(milk.isFavorite && model.fields?.isFavorite == true)
        #expect(!env.context.hasChanges)
        model.toggleFavorite()
        #expect(!milk.isFavorite)
    }

    @Test func consumeWithUndo() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 6)
        let model = model(env, eggs)
        let action = try #require(model.consume(item.publicId, amount: 2))
        #expect(action.kind == .consume)
        model.reload()
        #expect(model.stockTotalText == "4\u{00A0}pcs")
        #expect(model.history.first?.kind == .consumed)
        action.revert()
        model.reload()
        #expect(model.stockTotalText == "6\u{00A0}pcs")
        #expect(model.history.map(\.kind) == [.added])
    }

    @Test func consumeMoreThanInStockReportsTheError() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 2)
        let model = model(env, eggs)
        #expect(model.consume(item.publicId, amount: 3) == nil)
        #expect(model.errorMessage == ServiceError.quantityExceedsStock.errorDescription)
        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @Test func partialMoveWithUndo() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge, _) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        let model = model(env, eggs)
        let action = try #require(model.move(item.publicId, amount: 10, to: fridge.publicId))
        model.reload()
        #expect(Set(model.stock.map(\.locationName)) == ["Pantry", "Fridge"])
        #expect(model.stockTotalText == "12\u{00A0}pcs")
        action.revert()
        model.reload()
        #expect(model.stockTotalText == "12\u{00A0}pcs" && model.stockCount == 1)
    }

    @Test func moveToNoLocation() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, _, _) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3, location: pantry)
        let model = model(env, eggs)
        try #require(model.move(item.publicId, amount: 3, to: nil)).commit()
        #expect(item.storageLocation == nil)
    }

    @Test("Move targets are every other location of the space, searchable, plus no location")
    func moveTargets() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, _, _) = try locations(env)
        let home = try env.makeHousehold()
        try env.storageService().create(in: home, name: "Garage", color: nil, isFreezer: false)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3, location: pantry)
        let model = model(env, eggs)
        #expect(model.moveTargets(for: item.publicId, matching: "").map(\.name) == ["Fridge", "Freezer", nil])
        #expect(model.moveTargets(for: item.publicId, matching: "fre").map(\.name) == ["Freezer"])

        let loose = try env.stock(eggs, 1)
        #expect(model.moveTargets(for: loose.publicId, matching: "").map(\.name) == ["Pantry", "Fridge", "Freezer"])
    }

    @Test func deleteItemHidesUntilCommit() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3)
        let pending = PendingDeletions()
        let model = model(env, eggs, pending: pending)
        let action = try #require(model.deleteItem(item.publicId))
        #expect(model.stock.isEmpty)
        action.revert()
        #expect(model.stockCount == 1)
        try #require(model.deleteItem(item.publicId)).commit()
        model.reload()
        #expect(model.stock.isEmpty)
        #expect(model.history.map(\.kind) == [.deleted, .added])
    }

    @Test func deleteProductHidesUntilCommit() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let pending = PendingDeletions()
        let model = model(env, eggs, pending: pending)
        let action = try #require(model.deleteProduct())
        #expect(pending.contains(eggs.publicId))
        try action.commit()
        #expect(try env.count(Product.self) == 0)
    }

    @Test func readOnlyBlocksActions() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3)
        let model = model(env, eggs, canEdit: false)
        #expect(!model.canEdit)
        #expect(model.consume(item.publicId, amount: 1) == nil)
        #expect(model.errorMessage == ServiceError.readOnlySpace.errorDescription)
        #expect(model.deleteProduct() == nil)
        model.toggleFavorite()
        #expect(!eggs.isFavorite)
    }

    @Test("Amount sheets start with the full remaining amount and are capped at it")
    func amountForm() async throws {
        let env = try ServiceTestEnvironment()
        let flour = try await env.makeProduct("Flour", unit: .kilogram)
        let item = try env.stock(flour, Decimal(string: "1.5")!)
        let form = try #require(model(env, flour).amountForm(for: item.publicId))
        #expect(form.value == Decimal(string: "1.5")! && form.isValid)
        #expect(form.maximumText == "1.5\u{00A0}kg")
        form.text = "2"
        #expect(!form.isValid)
        form.text = "0"
        #expect(!form.isValid)
        form.text = "abc"
        #expect(form.value == nil && !form.isValid)
    }
}

@MainActor
@Suite("AmountFormModel")
struct AmountFormModelTests {
    static let en = Locale(identifier: "en_US")
    static let hu = Locale(identifier: "hu_HU")

    @Test func stepperStaysInsideTheRange() {
        let form = AmountFormModel(maximum: 3, unit: .piece, locale: Self.en)
        #expect(form.text == "3" && form.step == 1)
        form.increment()
        #expect(form.value == 3)
        form.decrement(); form.decrement()
        #expect(form.value == 1)
        form.decrement()
        #expect(form.value == 1)
        #expect(!form.canDecrement && form.canIncrement)
    }

    @Test("Steps follow the unit", arguments: [
        (MeasureUnit.kilogram, "0.1"), (.liter, "0.1"), (.gram, "10"), (.milliliter, "10"), (.piece, "1"), (.bottle, "1"),
    ])
    func steps(unit: MeasureUnit, step: String) {
        #expect(AmountFormModel(maximum: 100, unit: unit, locale: Self.en).step == Decimal(string: step)!)
    }

    @Test func decimalStepsAndLocaleSeparator() {
        let form = AmountFormModel(maximum: Decimal(string: "0.25")!, unit: .kilogram, locale: Self.hu)
        #expect(form.text == "0,25")
        form.decrement()
        #expect(form.text == "0,15")
        form.text = "0.2"
        #expect(form.value == Decimal(string: "0.2")! && form.isValid)
        form.increment()
        #expect(form.value == Decimal(string: "0.25")!)
    }
}

@MainActor
@Suite("ProductDetailModel edit and transfer")
struct ProductDetailEditTransferTests {
    func model(_ env: ServiceTestEnvironment, _ product: Product, spaces: [Space]) -> ProductDetailModel {
        let model = ProductDetailModel(product: product, products: env.productService(), inventory: env.inventoryService(),
                                       storageLocations: env.storageService(), pending: PendingDeletions(),
                                       userRecordName: ServiceTestEnvironment.user,
                                       locale: Locale(identifier: "en_US"), spaces: { spaces })
        model.reload()
        return model
    }

    @Test func editFormLoadsTheItem() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 10, expiresInDays: 20)
        let locations = ShoppingLocationService(spaceStore: env.spaceStore, context: env.context,
                                                userRecordName: ServiceTestEnvironment.user)
        let form = try #require(model(env, eggs, spaces: [env.personal]).editForm(for: item.publicId, locations: locations))
        #expect(form.isEditing && form.lots.lots[0].quantityText == "10")
        form.lots.lots[0].quantityText = "8"
        #expect(form.save() == [item])
        #expect(item.quantity == 8)
    }

    @Test("Transfer targets are the other spaces; moving copies the item there")
    func transfer() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold("Home")
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 6)
        let model = model(env, eggs, spaces: [env.personal, home])
        #expect(model.transferTargets.map(\.name) == ["Home"])
        #expect(model.transfer(item.publicId, to: home.publicId))
        model.reload()
        #expect(model.stock.isEmpty)
        #expect(try env.inventoryService().items(in: home).map(\.quantity) == [6])
    }

    @Test func noOtherSpaceMeansNoTargets() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        #expect(model(env, eggs, spaces: [env.personal]).transferTargets.isEmpty)
    }
}
