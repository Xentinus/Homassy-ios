import Foundation

/// The list the user last added an item to, per space (P4-03a). The add sheet presets its "Lista" row with it
/// when no list is filtered. N-02 reuses it for the "Add to list" quick action.
@MainActor
public final class LastUsedShoppingList {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func listID(for spaceID: UUID) -> UUID? {
        defaults.string(forKey: Self.key(spaceID)).flatMap(UUID.init(uuidString:))
    }

    public func record(_ listID: UUID, for spaceID: UUID) {
        defaults.set(listID.uuidString, forKey: Self.key(spaceID))
    }

    private static func key(_ spaceID: UUID) -> String { "shopping.lastList.\(spaceID.uuidString)" }
}
