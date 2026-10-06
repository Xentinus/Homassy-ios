import Foundation

/// Form state for creating or editing a product. Plain strings; the service trims and nils them.
public struct ProductDraft: Equatable, Sendable {
    public var name: String
    public var brand: String
    public var category: String
    public var barcode: String
    public var defaultUnit: MeasureUnit
    public var isFavorite: Bool
    public var notes: String
    /// Raw picked photo, or the stored image when editing. `nil` removes the image.
    public var imageData: Data?
    /// The product's web link as typed; the service trims it and adds https:// when there is no scheme.
    public var url: String

    public init(name: String = "", brand: String = "", category: String = "", barcode: String = "",
                defaultUnit: MeasureUnit = .piece, isFavorite: Bool = false,
                notes: String = "", imageData: Data? = nil, url: String = "") {
        self.name = name
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.defaultUnit = defaultUnit
        self.isFavorite = isFavorite
        self.notes = notes
        self.imageData = imageData
        self.url = url
    }

    @MainActor
    public init(product: Product) {
        self.init(name: product.name, brand: product.brand ?? "", category: product.category ?? "",
                  barcode: product.barcode ?? "", defaultUnit: product.defaultUnit,
                  isFavorite: product.isFavorite, notes: product.notes ?? "", imageData: product.image,
                  url: product.url ?? "")
    }
}
