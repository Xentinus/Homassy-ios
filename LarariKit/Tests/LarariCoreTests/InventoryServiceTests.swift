import CoreData
import Foundation
import Testing
@testable import LarariCore

extension ServiceTestEnvironment {
    static let fixedNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18, minute: 30))!
    }()

    static var budapest: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }

    func inventoryService(user: String = ServiceTestEnvironment.user,
                          canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) -> InventoryService {
        InventoryService(spaceStore: spaceStore, context: context, userRecordName: user, canEdit: canEdit,
                         calendar: Self.budapest, defaultCurrency: "HUF", now: { ServiceTestEnvironment.fixedNow })
    }

    func day(_ offset: Int) -> Date {
        Self.budapest.date(byAdding: .day, value: offset, to: Self.budapest.startOfDay(for: Self.fixedNow))!
    }

    @discardableResult
    func stock(_ product: Product, _ quantity: Decimal, location: StorageLocation? = nil,
               expiresInDays: Int? = nil) throws -> InventoryItem {
        // No purchase date, so already-expired fixtures pass the expiry-before-purchase rule.
        try inventoryService().addStock(product: product, quantity: quantity, unit: product.defaultUnit,
                                        expiresAt: expiresInDays.map(day), purchasedAt: nil, price: nil,
                                        currency: nil, storageLocation: location, shoppingLocation: nil)
    }
}

@MainActor
@Suite("InventoryService")
struct InventoryServiceTests {
    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test func addStockStoresEveryField() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let item = try env.inventoryService().addStock(
            product: milk, quantity: Self.d("1.5"), unit: .liter, expiresAt: env.day(5), purchasedAt: env.day(0),
            price: Self.d("459.90"), currency: nil, storageLocation: fridge, shoppingLocation: nil)
        #expect(item.product == milk)
        #expect(item.quantity == Self.d("1.5"))
        #expect(item.unit == .liter)
        #expect(item.expiresAt == env.day(5))
        #expect(item.purchasedAt == env.day(0))
        #expect(item.price == Self.d("459.90"))
        #expect(item.currency == "HUF")
        #expect(item.storageLocation == fridge)
        #expect(!item.isFullyConsumed && item.consumedAt == nil)
        #expect(item.createdBy == ServiceTestEnvironment.user)
        #expect(!env.context.hasChanges)
    }

    @Test("Quantity must be positive", arguments: ["0", "-1", "-0.5"])
    func addStockRejectsNonPositive(quantity: String) async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        #expect(throws: ServiceError.quantityMustBePositive) { try env.stock(milk, Self.d(quantity)) }
        #expect(try env.count(InventoryItem.self) == 0)
    }

    @Test func expiryMayNotPrecedePurchaseDay() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let service = env.inventoryService()
        let purchase = Self.dayAt(env.day(3), hour: 20)
        let sameDayEarlier = Self.dayAt(env.day(3), hour: 6)
        try service.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: sameDayEarlier, purchasedAt: purchase,
                             price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        #expect(throws: ServiceError.expiryBeforePurchase) {
            try service.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: env.day(2), purchasedAt: purchase,
                                 price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        }
        try service.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: purchase,
                             price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        try service.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: env.day(-9), purchasedAt: nil,
                             price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        #expect(try env.count(InventoryItem.self) == 3)
    }

    static func dayAt(_ day: Date, hour: Int) -> Date {
        ServiceTestEnvironment.budapest.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test func locationsMustBelongToTheSameSpace() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk")
        let garage = try env.storageService().create(in: home, name: "Garage", color: nil, isFreezer: false)
        #expect(throws: ServiceError.notFound) { try env.stock(milk, 1, location: garage) }
        let item = try env.stock(milk, 1)
        #expect(throws: ServiceError.notFound) { try env.inventoryService().move(item, to: garage) }
    }

    @Test func consumeWritesALogAndReducesQuantity() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3)
        let log = try env.inventoryService(user: ServiceTestEnvironment.otherUser).consume(item, quantity: 1)
        #expect(item.quantity == 2)
        #expect(log.quantity == 1)
        #expect(log.remaining == 2)
        #expect(log.consumedAt == ServiceTestEnvironment.fixedNow)
        #expect(log.inventoryItem == item)
        #expect(!item.isFullyConsumed)
        #expect(item.updatedBy == ServiceTestEnvironment.otherUser)
        #expect(!env.context.hasChanges)
    }

    @Test("Consuming more than is in stock is rejected, not clamped")
    func consumeRejectsMoreThanInStock() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let item = try env.stock(milk, 2)
        #expect(throws: ServiceError.quantityExceedsStock) { try env.inventoryService().consume(item, quantity: Self.d("2.001")) }
        #expect(item.quantity == 2)
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(try env.count(InventoryEvent.self, where: NSPredicate(format: "kindRaw == %@", "consumed")) == 0)
    }

    @Test func consumingEverythingFinishesTheItem() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let item = try env.stock(milk, 2)
        let log = try env.inventoryService().consume(item, quantity: 2)
        #expect(log.quantity == 2)
        #expect(log.remaining == 0)
        #expect(item.quantity == 0)
        #expect(item.isFullyConsumed)
        #expect(item.consumedAt == ServiceTestEnvironment.fixedNow)
        #expect(throws: ServiceError.quantityExceedsStock) { try env.inventoryService().consume(item, quantity: 1) }
    }

    @Test("Consuming nothing is rejected", arguments: ["0", "-2"])
    func consumeRejectsNonPositive(quantity: String) async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Eggs"), 3)
        #expect(throws: ServiceError.quantityMustBePositive) { try env.inventoryService().consume(item, quantity: Self.d(quantity)) }
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(item.quantity == 3)
    }

    @Test func markUsedUpLogsTheRemainder() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Rice", unit: .kilogram), Self.d("0.75"))
        let log = try env.inventoryService().markUsedUp(item)
        #expect(log.quantity == Self.d("0.75"))
        #expect(log.remaining == 0)
        #expect(item.isFullyConsumed)
    }

    @Test("Quantity and logs stay consistent over many consumptions")
    func consistency() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Flour", unit: .kilogram), 5)
        let service = env.inventoryService()
        for amount in ["0.5", "1", "0.25", "2", "1.25"] {
            let log = try service.consume(item, quantity: Self.d(amount))
            #expect(log.remaining == item.quantity)
        }
        let logs = try service.logs(for: item)
        let consumed = logs.reduce(Decimal(0)) { $0 + $1.quantity }
        #expect(consumed + item.quantity == 5)
        #expect(item.quantity == 0 && item.isFullyConsumed)
        #expect(logs.count == 5)
    }

    @Test func listsExcludeConsumedItems() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk")
        let open = try env.stock(milk, 1)
        let finished = try env.stock(milk, 1)
        try env.inventoryService().markUsedUp(finished)
        try env.stock(try await env.makeProduct("Soap", in: home), 1)
        let service = env.inventoryService()
        #expect(try service.items(in: env.personal) == [open])
        #expect(Set(try service.items(in: env.personal, includeConsumed: true)) == [open, finished])
        #expect(try service.items(for: milk) == [open])
        #expect(try service.logs(for: milk).count == 1)
        #expect(try service.item(publicId: open.publicId) == open)
    }

    @Test func moveAndDelete() async throws {
        let env = try ServiceTestEnvironment()
        let storage = env.storageService()
        let fridge = try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let item = try env.stock(try await env.makeProduct("Milk"), 2)
        let service = env.inventoryService()
        try service.move(item, to: fridge)
        #expect(item.storageLocation == fridge)
        try service.move(item, to: nil)
        #expect(item.storageLocation == nil)
        try service.consume(item, quantity: 1)
        try service.delete(item)
        #expect(try env.count(InventoryItem.self) == 0)
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(throws: ServiceError.notFound) { try service.delete(item) }
    }

    @Test func updateEditsAndReopensAnItem() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Milk", unit: .liter), 1)
        let service = env.inventoryService()
        try service.markUsedUp(item)
        try service.update(item, quantity: 2, unit: .liter, expiresAt: env.day(4), purchasedAt: env.day(0),
                           price: 300, currency: "EUR", storageLocation: nil)
        #expect(item.quantity == 2 && !item.isFullyConsumed && item.consumedAt == nil)
        #expect(item.currency == "EUR" && item.price == 300 && item.expiresAt == env.day(4))
        #expect(throws: ServiceError.quantityMustBePositive) {
            try service.update(item, quantity: 0, unit: .liter, expiresAt: nil, purchasedAt: nil, price: nil, currency: nil, storageLocation: nil)
        }
    }

    @Test func readOnlySpaceIsEnforced() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let item = try env.stock(milk, 2)
        let readOnly = env.inventoryService(canEdit: { _ in false })
        #expect(throws: ServiceError.readOnlySpace) {
            try readOnly.addStock(product: milk, quantity: 1, unit: .piece, expiresAt: nil, purchasedAt: nil,
                                  price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.consume(item, quantity: 1) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.markUsedUp(item) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.move(item, to: nil) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.delete(item) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.transfer(item, to: try env.makeHousehold()) }
        #expect(item.quantity == 2)
    }

    // MARK: Transfer

    @Test func transferMatchesByBarcodeFirst() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let source = try await env.makeProduct("Milk", barcode: "5991234567890")
        let target = try await env.makeProduct("Tej", in: home, barcode: "5991234567890")
        try await env.makeProduct("Milk", in: home)                   // same name, must lose to the barcode match
        let item = try env.stock(source, 2, expiresInDays: 3)

        let moved = try env.inventoryService().transfer(item, to: home)
        #expect(moved.product == target)
        #expect(item.isGone)
        #expect(try env.count(InventoryItem.self) == 1)
    }

    @Test func transferMatchesByNameCaseInsensitively() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let source = try await env.makeProduct("Túró Rudi")
        let target = try await env.makeProduct("túró rudi", in: home)
        let moved = try env.inventoryService().transfer(try env.stock(source, 4), to: home)
        #expect(moved.product == target)
        #expect(try env.count(Product.self, where: NSPredicate(format: "space == %@", home)) == 1)
    }

    @Test func transferCopiesProductFieldsLogsAndPurchaseData() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let storage = env.storageService()
        let fridge = try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let homeFridge = try storage.create(in: home, name: "fridge", color: nil, isFreezer: false)
        let photo = TestImages.jpeg(width: 400, height: 300)
        let source = try await env.productService().create(in: env.personal, draft: ProductDraft(
            name: "Cheese", brand: "Pannónia", category: "Dairy", barcode: "", defaultUnit: .gram,
            isFavorite: true, notes: "Sliced", imageData: photo, url: "https://example.com/cheese"))
        let service = env.inventoryService()
        let item = try service.addStock(product: source, quantity: 250, unit: .gram, expiresAt: env.day(6),
                                        purchasedAt: env.day(-1), price: 1290, currency: "HUF",
                                        storageLocation: fridge, shoppingLocation: nil)
        try service.consume(item, quantity: 50)

        let moved = try service.transfer(item, to: home)
        let copy = try #require(moved.product)
        #expect(copy != source && copy.space == home)
        #expect(copy.name == "Cheese" && copy.brand == "Pannónia" && copy.category == "Dairy")
        #expect(copy.defaultUnit == .gram && copy.isFavorite && copy.notes == "Sliced")
        #expect(copy.image == source.image)
        #expect(copy.url == "https://example.com/cheese")
        #expect(moved.quantity == 200 && moved.unit == .gram)
        #expect(moved.expiresAt == env.day(6) && moved.purchasedAt == env.day(-1))
        #expect(moved.price == 1290 && moved.currency == "HUF")
        #expect(moved.storageLocation == homeFridge)
        let logs = try service.logs(for: moved)
        #expect(logs.count == 1 && logs.first?.quantity == 50 && logs.first?.remaining == 200)
        #expect(try env.count(ConsumptionLog.self) == 1)
        #expect(!source.isGone)
    }

    @Test func transferToTheSameSpaceIsANoOp() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Milk"), 1)
        #expect(try env.inventoryService().transfer(item, to: env.personal) == item)
    }
}
