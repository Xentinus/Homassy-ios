import Foundation

/// Navigation value for a product detail. Codable, so the tab's restored path can hold it.
struct ProductRoute: Hashable, Codable {
    let id: UUID
}
