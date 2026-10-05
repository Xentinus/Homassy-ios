import Foundation

/// What a secondary iPad window shows (N-03): one shopping list or one product. `openWindow(value:)` needs it
/// Codable and Hashable, and SwiftUI stores it to restore the window, so the JSON is a stable `kind` + `id` pair
/// rather than the synthesized enum shape.
public enum WindowRoute: Hashable, Codable, Sendable {
    case shoppingList(UUID)
    case product(UUID)

    /// The user activity a dragged card carries to create a window (Task 8). Declared in Info.plist
    /// `NSUserActivityTypes`, and matched by the route window group's `handlesExternalEvents`.
    public static let activityType = "com.homassy.app.window"

    private enum Kind: String, Codable {
        case shoppingList, product
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    /// The list's or the product's `publicId`.
    public var id: UUID {
        switch self {
        case let .shoppingList(id), let .product(id): id
        }
    }

    private var kind: Kind {
        switch self {
        case .shoppingList: .shoppingList
        case .product: .product
        }
    }

    private init(kind: Kind, id: UUID) {
        switch kind {
        case .shoppingList: self = .shoppingList(id)
        case .product: self = .product(id)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try container.decode(Kind.self, forKey: .kind), id: try container.decode(UUID.self, forKey: .id))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
    }

    /// Plist-safe payload for an `NSUserActivity`.
    public var userInfo: [String: String] {
        ["kind": kind.rawValue, "id": id.uuidString]
    }

    /// Reads a user activity's `userInfo`; nil when it is not a Homassy window route.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let kind = (userInfo["kind"] as? String).flatMap(Kind.init(rawValue:)),
              let id = (userInfo["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        self.init(kind: kind, id: id)
    }
}
