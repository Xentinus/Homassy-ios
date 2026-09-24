import Foundation

/// Fixture data for `-uiTestSeed` launches. Only ever runs against the in-memory store.
@MainActor
public enum UITestSeed {
    public static let knownBarcode = "5991234567890"

    public static func populate(_ container: ServiceContainer, in space: Space) async throws {
        guard try container.products.products(in: space).isEmpty else { return }

        let locations = container.storageLocations
        try locations.create(in: space, name: "Fridge", color: .blue, isFreezer: false)
        try locations.create(in: space, name: "Pantry", color: .orange, isFreezer: false)
        try locations.create(in: space, name: "Freezer", color: .teal, isFreezer: true)

        let products = container.products
        try await products.create(in: space, draft: ProductDraft(name: "Milk", brand: "Mizo", category: "Dairy",
                                                                 barcode: knownBarcode, defaultUnit: .liter))
        try await products.create(in: space, draft: ProductDraft(name: "Bread", category: "Bakery", defaultUnit: .piece))
        try await products.create(in: space, draft: ProductDraft(name: "Eggs", category: "Dairy", defaultUnit: .piece))
        try await products.create(in: space, draft: ProductDraft(name: "Apples", category: "Fruit", defaultUnit: .kilogram))
    }
}
