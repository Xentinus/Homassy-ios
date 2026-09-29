import Foundation

/// The list the user last added an item to, per space (P4-03a). The add sheet presets its "Lista" row with it
/// when no list is filtered. N-02's quick actions use the last one across all spaces (`lastReference`).
@MainActor
public final class LastUsedShoppingList {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func listID(for spaceID: UUID) -> UUID? {
        defaults.string(forKey: Self.key(spaceID)).flatMap(UUID.init(uuidString:))
    }

    /// The list added to last in any space (N-02: the Home Screen menu offers it).
    public var lastReference: ShoppingListReference? {
        guard let parts = defaults.string(forKey: Self.lastKey)?.split(separator: " "), parts.count == 2,
              let space = UUID(uuidString: String(parts[0])), let list = UUID(uuidString: String(parts[1]))
        else { return nil }
        return ShoppingListReference(spaceID: space, listID: list)
    }

    public func record(_ listID: UUID, for spaceID: UUID) {
        defaults.set(listID.uuidString, forKey: Self.key(spaceID))
        defaults.set("\(spaceID.uuidString) \(listID.uuidString)", forKey: Self.lastKey)
    }

    private static let lastKey = "shopping.lastList"

    private static func key(_ spaceID: UUID) -> String { "shopping.lastList.\(spaceID.uuidString)" }
}
