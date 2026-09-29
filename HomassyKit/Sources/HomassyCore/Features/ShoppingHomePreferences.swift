import Foundation

/// How the Shopping tab groups the cards (P4-03a): one section per list, or per store.
public enum ShoppingGrouping: String, Sendable, CaseIterable {
    case list, store
}

/// The Shopping tab's remembered choices: the list filter per space, and the grouping per device.
@MainActor
public final class ShoppingHomePreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func filter(for spaceID: UUID) -> UUID? {
        defaults.string(forKey: Self.filterKey(spaceID)).flatMap(UUID.init(uuidString:))
    }

    public func setFilter(_ listID: UUID?, for spaceID: UUID) {
        if let listID {
            defaults.set(listID.uuidString, forKey: Self.filterKey(spaceID))
        } else {
            defaults.removeObject(forKey: Self.filterKey(spaceID))
        }
    }

    public var grouping: ShoppingGrouping {
        get { defaults.string(forKey: Self.groupingKey).flatMap(ShoppingGrouping.init(rawValue:)) ?? .list }
        set { defaults.set(newValue.rawValue, forKey: Self.groupingKey) }
    }

    private static let groupingKey = "shoppingHome.grouping"
    private static func filterKey(_ spaceID: UUID) -> String { "shoppingHome.filter.\(spaceID.uuidString)" }
}
