import Foundation

/// An open shopping-list item assigned to a store (P4-06).
public struct WaitingItem: Sendable, Equatable {
    public let name: String
    public let spaceName: String
    public let storeName: String
    public let storeCoordinate: Coordinate?
    public let storeLastUsedAt: Date?
    public let spaceID: UUID?

    public init(name: String, spaceName: String, storeName: String, storeCoordinate: Coordinate?, storeLastUsedAt: Date?,
                spaceID: UUID? = nil) {
        self.name = name
        self.spaceName = spaceName
        self.storeName = storeName
        self.storeCoordinate = storeCoordinate
        self.storeLastUsedAt = storeLastUsedAt
        self.spaceID = spaceID
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
    /// The space a tap opens: the one with most of the waiting items.
    public let targetSpaceID: UUID?

    public init(identifier: String, title: String, body: String, center: Coordinate, radius: Double,
                targetSpaceID: UUID? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.center = center
        self.radius = radius
        self.targetSpaceID = targetSpaceID
    }
}

/// Pure: waiting items and nearby branches in, at most `budget` reminders out (spec 2026-09-26).
public enum StoreReminderPlanner {
    public static let identifierPrefix = "store-"
    public static let maxRegions = 20
    public static let regionRadius: Double = 150
    public static let searchRadius: Double = 15_000
    static let duplicateDistance: Double = 50

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
        // Only the count, never item names; a tap opens the Shopping tab (user request, 2026-09-26).
        let body = CoreLocalization.format("store.reminder.count %lld", locale: locale, group.items.count)
        let slug = group.key.replacingOccurrences(of: " ", with: "_")
        return PlannedStoreReminder(
            identifier: "\(identifierPrefix)\(slug)-\(rank)",
            title: CoreLocalization.format("store.reminder.title %@", locale: locale, group.displayName),
            body: body, center: center, radius: regionRadius,
            targetSpaceID: NotificationPlanner.mostCommonSpace(group.items.map(\.spaceID)))
    }

    private static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        StoreResult(mapItemIdentifier: "", name: "", latitude: a.latitude, longitude: a.longitude)
            .distance(toLatitude: b.latitude, longitude: b.longitude)
    }
}

extension StoreReminderPlanner {
    /// The chain key of a reminder identifier (`store-<key, spaces as _>-<rank>`), for the shopping Live Activity
    /// (N-04). Chain keys never contain `_` or `-` (`ChainKey` splits on everything but letters and digits).
    public static func chainKey(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(identifierPrefix.count)
        guard let dash = rest.lastIndex(of: "-") else { return nil }
        let slug = rest[..<dash]
        return slug.isEmpty ? nil : slug.replacingOccurrences(of: "_", with: " ")
    }
}
