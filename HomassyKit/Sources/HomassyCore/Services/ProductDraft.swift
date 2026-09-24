import Foundation

/// Form state for creating or editing a product. Plain strings; the service trims and nils them.
public struct ProductDraft: Equatable, Sendable {
    public var name: String
    public var brand: String
    public var category: String
    public var barcode: String
    public var defaultUnit: MeasureUnit
    public var isEatable: Bool
    public var isFavorite: Bool
    public var notes: String
    /// Raw picked photo, or the stored image when editing. `nil` removes the image.
    public var imageData: Data?

    public init(name: String = "", brand: String = "", category: String = "", barcode: String = "",
                defaultUnit: MeasureUnit = .piece, isEatable: Bool = true, isFavorite: Bool = false,
                notes: String = "", imageData: Data? = nil) {
        self.name = name
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.defaultUnit = defaultUnit
        self.isEatable = isEatable
        self.isFavorite = isFavorite
        self.notes = notes
        self.imageData = imageData
    }

    @MainActor
    public init(product: Product) {
        self.init(name: product.name, brand: product.brand ?? "", category: product.category ?? "",
                  barcode: product.barcode ?? "", defaultUnit: product.defaultUnit, isEatable: product.isEatable,
                  isFavorite: product.isFavorite, notes: product.notes ?? "", imageData: product.image)
    }
}
