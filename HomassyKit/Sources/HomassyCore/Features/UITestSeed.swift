import Foundation

/// Fixture data for `-uiTestSeed` launches. Only ever runs against the in-memory store.
@MainActor
public enum UITestSeed {
    public static let knownBarcode = "5991234567890"

    public static func populate(_ container: ServiceContainer, in space: Space) async throws {
        guard try container.products.products(in: space).isEmpty else { return }

        let locations = container.storageLocations
        let fridge = try locations.create(in: space, name: "Fridge", color: .blue, isFreezer: false)
        let pantry = try locations.create(in: space, name: "Pantry", color: .orange, isFreezer: false)
        try locations.create(in: space, name: "Freezer", color: .teal, isFreezer: true)

        let products = container.products
        let milk = try await products.create(in: space, draft: ProductDraft(name: "Milk", brand: "Mizo", category: "Dairy",
                                                                            barcode: knownBarcode, defaultUnit: .liter))
        let bread = try await products.create(in: space, draft: ProductDraft(name: "Bread", category: "Bakery", defaultUnit: .piece))
        let eggs = try await products.create(in: space, draft: ProductDraft(name: "Eggs", category: "Dairy", defaultUnit: .piece))
        let apples = try await products.create(in: space, draft: ProductDraft(name: "Apples", category: "Fruit", defaultUnit: .kilogram))

        try container.shoppingLocations.upsert(
            StoreResult(mapItemIdentifier: "uitest-corner-shop", name: "Corner Shop", latitude: 47.4979, longitude: 19.0402),
            in: space)
        if let address = StoreAddress(short: "Fő utca 1., Budapest") {
            container.storeAddressCache.set(address, for: "uitest-corner-shop")
        }

        // P2-08's inventory fixture, brought forward by P2-07 for the product detail (Milk also has a price).
        let inventory = container.inventory
        let calendar = inventory.calendar
        let today = calendar.startOfDay(for: inventory.currentDate())
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let purchased = day(-3)
        try inventory.addStock(product: bread, quantity: 1, unit: .piece, expiresAt: day(-1), purchasedAt: purchased,
                               price: nil, currency: nil, storageLocation: pantry, shoppingLocation: nil)
        try inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: day(2), purchasedAt: purchased,
                               price: 459, currency: "HUF", storageLocation: fridge, shoppingLocation: nil)
        try inventory.addStock(product: apples, quantity: Decimal(string: "1.5", locale: Locale(identifier: "en_US_POSIX")) ?? 1,
                               unit: .kilogram, expiresAt: day(10), purchasedAt: purchased,
                               price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        try inventory.addStock(product: eggs, quantity: 10, unit: .piece, expiresAt: day(20), purchasedAt: purchased,
                               price: nil, currency: nil, storageLocation: fridge, shoppingLocation: nil)
    }
}
