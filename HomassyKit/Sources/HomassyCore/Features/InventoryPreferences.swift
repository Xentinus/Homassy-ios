import Foundation

/// How the Inventory tab groups the cards (P2-08e): by storage location with "Expiring soon" on top, by name in
/// letter sections, or by expiry in time bands.
public enum InventoryGrouping: String, Sendable, CaseIterable {
    case location, name, expiry
}

/// The Inventory tab's remembered grouping, per device, like the Shopping grouping.
@MainActor
public final class InventoryPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var grouping: InventoryGrouping {
        get { defaults.string(forKey: Self.groupingKey).flatMap(InventoryGrouping.init(rawValue:)) ?? .location }
        set { defaults.set(newValue.rawValue, forKey: Self.groupingKey) }
    }

    private static let groupingKey = "inventory.grouping"
}
