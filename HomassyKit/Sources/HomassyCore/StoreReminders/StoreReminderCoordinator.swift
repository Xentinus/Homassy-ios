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
                                   storeName: store.name, storeCoordinate: coordinate, storeLastUsedAt: store.lastUsedAt)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func refresh() async {
        guard isEnabled(), let location, location.access == .authorized else {
            lastPlan = await scheduler.rescheduleStoreReminders([])
            return
        }
        let groups = StoreReminderPlanner.groups((try? Self.waitingItems(in: context)) ?? [])
        guard !groups.isEmpty else {
            lastPlan = await scheduler.rescheduleStoreReminders([])
            return
        }
        let position = await location.currentCoordinate()
        var branches: [String: [StoreResult]] = [:]
        if let position {
            for group in groups {
                branches[group.key] = (try? await search.search(text: group.displayName, latitude: position.latitude,
                                                                longitude: position.longitude)) ?? []
            }
        }
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
