import Foundation

/// An open shopping-list item assigned to a store (P4-06).
public struct WaitingItem: Sendable, Equatable {
    public let name: String
    public let spaceName: String
    public let storeName: String
    public let storeCoordinate: Coordinate?
    public let storeLastUsedAt: Date?

    public init(name: String, spaceName: String, storeName: String, storeCoordinate: Coordinate?, storeLastUsedAt: Date?) {
        self.name = name
        self.spaceName = spaceName
        self.storeName = storeName
        self.storeCoordinate = storeCoordinate
        self.storeLastUsedAt = storeLastUsedAt
    }
}

/// Waiting items of one chain, from any space and any of its stores.
public struct StoreReminderGroup: Sendable, Equatable {
    public let key: String
    public let displayName: String
    public let items: [WaitingItem]
}

/// One location-triggered notification: a 150 m circle around a branch.
public struct PlannedStoreReminder: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    public let center: Coordinate
    public let radius: Double

    public init(identifier: String, title: String, body: String, center: Coordinate, radius: Double) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.center = center
        self.radius = radius
    }
}

/// Pure: waiting items and nearby branches in, at most `budget` reminders out (spec 2026-09-26).
public enum StoreReminderPlanner {
    public static let identifierPrefix = "store-"
    public static let maxRegions = 20
    public static let regionRadius: Double = 150
    public static let searchRadius: Double = 15_000
    static let duplicateDistance: Double = 50
    static let namesShown = 3

    public static func groups(_ items: [WaitingItem]) -> [StoreReminderGroup] {
        Dictionary(grouping: items.filter { !ChainKey.make($0.storeName).isEmpty }) { ChainKey.make($0.storeName) }
            .map { key, items in
                StoreReminderGroup(key: key, displayName: ChainKey.displayName(of: items.map(\.storeName)), items: items)
            }
            .sorted { $0.key < $1.key }
    }

    public static func plan(groups: [StoreReminderGroup], branches: [String: [StoreResult]],
                            position: Coordinate?, budget: Int, locale: Locale) -> [PlannedStoreReminder] {
        let candidates = groups.map { candidates(for: $0, branches: branches[$0.key] ?? [], position: position) }
        var result: [PlannedStoreReminder] = []
        var rank = 0
        while result.count < budget, candidates.contains(where: { $0.count > rank }) {
            for (index, group) in groups.enumerated() where result.count < budget && candidates[index].count > rank {
                result.append(reminder(for: group, at: candidates[index][rank], rank: rank, locale: locale))
            }
            rank += 1
        }
        return result
    }

    /// Assigned stores first (most recently used first), then branches of the same chain within 15 km; sorted by
    /// distance when the position is known; near duplicates (under 50 m) collapse.
    private static func candidates(for group: StoreReminderGroup, branches: [StoreResult], position: Coordinate?) -> [Coordinate] {
        let assigned = group.items
            .sorted { ($0.storeLastUsedAt ?? .distantPast) > ($1.storeLastUsedAt ?? .distantPast) }
            .compactMap(\.storeCoordinate)
        var nearby: [Coordinate] = []
        if let position {
            nearby = branches
                .filter { ChainKey.make($0.name) == group.key }
                .filter { $0.distance(toLatitude: position.latitude, longitude: position.longitude) <= searchRadius }
                .map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
        var ordered = assigned + nearby
        if let position {
            ordered.sort { distance($0, position) < distance($1, position) }
        }
        var unique: [Coordinate] = []
        for coordinate in ordered where !unique.contains(where: { distance($0, coordinate) < duplicateDistance }) {
            unique.append(coordinate)
        }
        return unique
    }

    private static func reminder(for group: StoreReminderGroup, at center: Coordinate, rank: Int,
                                 locale: Locale) -> PlannedStoreReminder {
        let count = CoreLocalization.format("store.reminder.count %lld", locale: locale, group.items.count)
        let body = CoreLocalization.format("notification.body %@ %@", locale: locale, count, names(group.items, locale: locale))
        let slug = group.key.replacingOccurrences(of: " ", with: "_")
        return PlannedStoreReminder(
            identifier: "\(identifierPrefix)\(slug)-\(rank)",
            title: CoreLocalization.format("store.reminder.title %@", locale: locale, group.displayName),
            body: body, center: center, radius: regionRadius)
    }

    static func names(_ items: [WaitingItem], locale: Locale) -> String {
        let showSpaces = Set(items.map(\.spaceName)).count > 1
        let sorted = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let shown = sorted.prefix(namesShown).map { showSpaces ? "\($0.name) (\($0.spaceName))" : $0.name }
        let joined = shown.joined(separator: ", ")
        let remaining = sorted.count - shown.count
        return remaining > 0 ? CoreLocalization.format("notification.names.more %@ %lld", locale: locale, joined, remaining) : joined
    }

    private static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        StoreResult(mapItemIdentifier: "", name: "", latitude: a.latitude, longitude: a.longitude)
            .distance(toLatitude: b.latitude, longitude: b.longitude)
    }
}
