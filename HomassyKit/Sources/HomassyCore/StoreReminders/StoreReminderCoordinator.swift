import CoreData
import Foundation

/// Keeps the store arrival reminders current (P4-06): open items assigned to a store, grouped by chain, scheduled on
/// the nearest branches. Switched off, without location permission or without items it only removes them.
@MainActor
public final class StoreReminderCoordinator {
    public enum Trigger: String, Sendable { case foreground, localSave, remoteChange, authorization }

    public private(set) var lastPlan: [PlannedStoreReminder] = []
    public private(set) var pendingRefresh: Task<Void, Never>?

    private let context: NSManagedObjectContext
    private let scheduler: NotificationScheduler
    private let search: any StoreSearching
    private let location: (any LocationAuthorizing)?
    private let isEnabled: @MainActor () -> Bool
    private let locale: Locale
    private let debounce: Duration

    public init(context: NSManagedObjectContext, center: any NotificationCentering, search: any StoreSearching,
                location: (any LocationAuthorizing)?, isEnabled: @escaping @MainActor () -> Bool,
                locale: Locale = .current, debounce: Duration = .milliseconds(500)) {
        self.context = context
        self.scheduler = NotificationScheduler(center: center)
        self.search = search
        self.location = location
        self.isEnabled = isEnabled
        self.locale = locale
        self.debounce = debounce
    }

    public static func waitingItems(in context: NSManagedObjectContext) throws -> [WaitingItem] {
        try context.fetchEntities(ShoppingListItem.self,
                                  where: NSPredicate(format: "isPurchased == NO AND shoppingLocation != nil"))
            .compactMap { item in
                guard let store = item.shoppingLocation else { return nil }
                let coordinate = store.latitude.flatMap { latitude in
                    store.longitude.map { Coordinate(latitude: latitude, longitude: $0) }
                }
                return WaitingItem(name: ShoppingService.displayName(of: item),
                                   spaceName: item.shoppingList?.space?.name ?? "",
                                   storeName: store.name, storeCoordinate: coordinate, storeLastUsedAt: store.lastUsedAt,
                                   spaceID: item.shoppingList?.space?.publicId)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func refresh() async {
        await refresh(position: .live)
    }

    /// Background app refresh (N-01). When In Use location gives no live position in the background, so this uses
    /// the last known one. Without it, or when a branch search fails (offline), the pending reminders stay as they
    /// are rather than shrinking to the assigned stores; switched off, without permission or with nothing waiting it still removes them.
    public func refreshInBackground() async {
        await refresh(position: .lastKnown)
    }

    private enum PositionSource { case live, lastKnown }

    private func refresh(position source: PositionSource) async {
        guard isEnabled(), let location, location.access == .authorized else {
            lastPlan = await scheduler.rescheduleStoreReminders([])
            return
        }
        let groups = StoreReminderPlanner.groups((try? Self.waitingItems(in: context)) ?? [])
        guard !groups.isEmpty else {
            lastPlan = await scheduler.rescheduleStoreReminders([])
            return
        }
        let position: Coordinate?
        switch source {
        case .live: position = await location.currentCoordinate()
        case .lastKnown: position = location.lastKnownCoordinate
        }
        if position == nil, source == .lastKnown { return }
        var branches: [String: [StoreResult]] = [:]
        if let position {
            for group in groups {
                // An expired background run stops searching; nothing has been rescheduled yet.
                guard !Task.isCancelled else { return }
                do {
                    branches[group.key] = try await search.search(text: group.displayName, latitude: position.latitude,
                                                                  longitude: position.longitude)
                } catch {
                    // Offline in the background: keep what the last foreground run planned, like a missing position.
                    if source == .lastKnown { return }
                    branches[group.key] = []
                }
            }
        }
        // An expired background run (or a newer foreground refresh) must not replace the reminders half-way.
        guard !Task.isCancelled else { return }
        let plan = StoreReminderPlanner.plan(groups: groups, branches: branches, position: position,
                                             budget: StoreReminderPlanner.maxRegions, locale: locale)
        lastPlan = await scheduler.rescheduleStoreReminders(plan)
    }

    /// Coalesces bursts (a save storm, several remote changes) into one refresh after `debounce`.
    public func scheduleRefresh(_ trigger: Trigger) {
        pendingRefresh?.cancel()
        let delay = debounce
        pendingRefresh = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
