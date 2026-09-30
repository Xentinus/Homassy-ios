import CoreData
import Foundation
import HomassyShared
import Observation

/// Runs the shopping Live Activity (N-04). `evaluate` on every foreground starts it at a store with open items
/// (D9 B: there is no button), switches when the user is at another store (one at a time), and ends it when the app
/// opens more than 1 km away. `refresh` follows every change; the last row bought shows "All done" for 5 minutes
/// (D4 A). A swiped-away activity is not started again at that place until the user left or 4 hours passed.
@MainActor
@Observable
public final class ShoppingActivityCoordinator {
    public static let staleInterval: TimeInterval = 60 * 60
    public static let relevance: Double = 100
    public static let finishedLinger: TimeInterval = 5 * 60
    public static let suppressionLifetime: TimeInterval = 4 * 60 * 60

    public private(set) var current: ShoppingActivityTarget?
    @ObservationIgnored public private(set) var pendingRefresh: Task<Void, Never>?

    @ObservationIgnored private var activityID: String?
    @ObservationIgnored private var progress: ShoppingActivityProgress?
    @ObservationIgnored private var lastContent: ShoppingActivityContent?
    @ObservationIgnored private let shopping: ShoppingService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let controller: any LiveActivityControlling
    @ObservationIgnored private let memory: ShoppingActivityMemory
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let debounce: Duration

    public init(shopping: ShoppingService, inventory: InventoryService, pending: PendingDeletions,
                controller: any LiveActivityControlling, memory: ShoppingActivityMemory, locale: Locale = .current,
                now: @escaping () -> Date = { Date() }, debounce: Duration = .milliseconds(500)) {
        self.shopping = shopping
        self.inventory = inventory
        locations = ShoppingLocationService(spaceStore: shopping.spaceStore, context: shopping.context,
                                            userRecordName: shopping.userRecordName)
        self.pending = pending
        self.controller = controller
        self.memory = memory
        self.locale = locale
        self.now = now
        self.debounce = debounce
    }

    // MARK: Entry points

    public func evaluate(position: Coordinate?, branches: [ChainBranch], preferredSpaceID: UUID?) async {
        await reconcile()
        guard let position else {
            await refresh()
            return
        }
        liftSuppression(at: position)
        if let center = current?.center,
           ShoppingActivityTrigger.distance(center, position) > ShoppingActivityTrigger.leaveDistance {
            await end(content: nil, dismissal: .immediate)
        }
        let stores = (try? ShoppingActivityTrigger.waitingStores(in: shopping.context, pending: pending)) ?? []
        guard let target = ShoppingActivityTrigger.target(position: position, stores: stores, branches: branches,
                                                          preferredSpaceID: preferredSpaceID) else {
            await refresh()
            return
        }
        guard !isCurrent(target), !isSuppressed(target), controller.areActivitiesEnabled else {
            await refresh()
            return
        }
        await start(target)
    }

    public func refresh() async {
        await reconcile()
        guard let current, let activityID, var progress else { return }
        guard let space = space(current.spaceID), let snapshot = try? snapshot(of: current.scope, in: space) else {
            await end(content: nil, dismissal: .immediate)
            return
        }
        if !current.scope.isChain, snapshot.title == nil {             // the store(s) were deleted
            await end(content: nil, dismissal: .immediate)
            return
        }
        progress.observe(openKeys: Set(snapshot.rows.map(\.id)))
        self.progress = progress
        let content = ShoppingActivityState.content(
            title: snapshot.title ?? lastContent?.title ?? "", spaceName: space.name, listCount: snapshot.listCount,
            rows: snapshot.rows, doneCount: progress.doneCount, canTick: shopping.canEdit(space))
        if content.isFinished {
            await end(content: content, dismissal: .after(now().addingTimeInterval(Self.finishedLinger)))
        } else if content != lastContent {
            lastContent = content
            await controller.update(id: activityID, content: content, staleDate: staleDate(), relevance: Self.relevance)
        }
    }

    /// Coalesces a save storm into one refresh after `debounce`.
    public func scheduleRefresh() {
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

    /// `TickShoppingItemIntent` through `ShoppingTickBridge`, possibly in a process launched just for it.
    public func tick(itemIDs: [UUID]) async {
        await reconcile()
        // A read-only household or a vanished item buys nothing; the refresh shows the real state either way.
        _ = try? ShoppingActivityActions.purchase(itemIDs: itemIDs, shopping: shopping, inventory: inventory,
                                                  pending: pending)
        await refresh()
    }

    // MARK: Lifecycle

    private func start(_ target: ShoppingActivityTarget) async {
        guard let space = space(target.spaceID), let snapshot = try? snapshot(of: target.scope, in: space),
              let title = snapshot.title, !snapshot.rows.isEmpty else { return }
        // A set of stores that grew keeps what was already bought; another place starts from zero.
        var carriedDone = 0
        if let running = current, running.spaceID == target.spaceID,
           !storeIDs(running.scope).isDisjoint(with: storeIDs(target.scope)) {
            carriedDone = progress?.doneCount ?? 0
        }
        if current != nil { await end(content: nil, dismissal: .immediate) }          // D5: one at a time
        let content = ShoppingActivityState.content(title: title, spaceName: space.name,
                                                    listCount: snapshot.listCount, rows: snapshot.rows,
                                                    doneCount: carriedDone, canTick: shopping.canEdit(space))
        do {
            let id = try controller.start(ShoppingActivityRequest(spaceID: target.spaceID, scope: target.scope,
                                                                  content: content, staleDate: staleDate(),
                                                                  relevance: Self.relevance))
            activityID = id
            current = target
            progress = ShoppingActivityProgress(openKeys: Set(snapshot.rows.map(\.id)), carriedDone: carriedDone)
            lastContent = content
            memory.started = .init(activityID: id, spaceID: target.spaceID, scope: target.scope, center: target.center)
        } catch {
            // iOS refused (turned off, too many activities): the next foreground tries again.
        }
    }

    private func end(content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async {
        guard let id = activityID else { return }
        activityID = nil
        current = nil
        progress = nil
        lastContent = nil
        memory.started = nil
        await controller.end(id: id, content: content, dismissal: dismissal)
    }

    /// Brings the in-memory state in line with what the system shows: an activity that disappeared without the app
    /// ending it was swiped away (or reached the 8-hour limit) and suppresses its place; an activity an earlier
    /// process started is adopted, extra ones end (D5).
    private func reconcile() async {
        let running = controller.running()
        if let activityID {
            if !running.contains(where: { $0.id == activityID }) { swipedAway() }
            return
        }
        if let started = memory.started, !running.contains(where: { $0.id == started.activityID }) {
            memory.suppressed = .init(spaceID: started.spaceID, scope: started.scope, center: started.center, since: now())
            memory.started = nil
        }
        let remembered = memory.started
        guard let first = running.first(where: { $0.id == remembered?.activityID }) ?? running.first else { return }
        for extra in running where extra.id != first.id {
            await controller.end(id: extra.id, content: nil, dismissal: .immediate)
        }
        let target = ShoppingActivityTarget(spaceID: first.spaceID, scope: first.scope,
                                            center: remembered?.activityID == first.id ? remembered?.center : nil)
        let openKeys = space(first.spaceID)
            .flatMap { try? snapshot(of: first.scope, in: $0) }
            .map { Set($0.rows.map(\.id)) } ?? []
        // Rows that left while no process ran count as done too.
        let carried = first.content.doneCount + max(0, first.content.remainingCount - openKeys.count)
        activityID = first.id
        current = target
        progress = ShoppingActivityProgress(openKeys: openKeys, carriedDone: carried)
        lastContent = first.content
        memory.started = .init(activityID: first.id, spaceID: first.spaceID, scope: first.scope, center: target.center)
    }

    private func swipedAway() {
        if let current {
            memory.suppressed = .init(spaceID: current.spaceID, scope: current.scope, center: current.center, since: now())
        }
        activityID = nil
        current = nil
        progress = nil
        lastContent = nil
        memory.started = nil
    }

    // MARK: Helpers

    private func liftSuppression(at position: Coordinate) {
        guard let suppressed = memory.suppressed else { return }
        let expired = now().timeIntervalSince(suppressed.since) > Self.suppressionLifetime
        let left = suppressed.center.map {
            ShoppingActivityTrigger.distance($0, position) > ShoppingActivityTrigger.leaveDistance
        } ?? false
        if expired || left { memory.suppressed = nil }
    }

    /// The running activity already covers the target: the same scope, or a set of stores that only shrank
    /// (the rows of one store were all bought) in the same space.
    private func isCurrent(_ target: ShoppingActivityTarget) -> Bool {
        guard let current, current.spaceID == target.spaceID else { return false }
        if current.scope == target.scope { return true }
        let ids = storeIDs(target.scope)
        return !ids.isEmpty && ids.isSubset(of: storeIDs(current.scope))
    }

    /// A swiped-away activity suppresses its place, not just its exact scope: the same store, the same chain, or
    /// anything within the arrival radius of where it was swiped.
    private func isSuppressed(_ target: ShoppingActivityTarget) -> Bool {
        guard let suppressed = memory.suppressed, suppressed.spaceID == target.spaceID else { return false }
        if !storeIDs(suppressed.scope).isDisjoint(with: storeIDs(target.scope)) { return true }
        if case let .chain(key) = suppressed.scope, case let .chain(other) = target.scope, key == other { return true }
        if let a = suppressed.center, let b = target.center {
            return ShoppingActivityTrigger.distance(a, b) <= ShoppingActivityTrigger.arrivalRadius
        }
        return false
    }

    private func storeIDs(_ scope: ShoppingActivityScope) -> Set<UUID> {
        switch scope {
        case let .store(id): [id]
        case let .stores(ids): Set(ids)
        case .chain: []
        }
    }

    private func staleDate() -> Date { now().addingTimeInterval(Self.staleInterval) }

    private func space(_ id: UUID) -> Space? {
        (try? shopping.spaceStore.allSpaces())?.first { $0.publicId == id && !$0.isGone }
    }

    private struct Snapshot {
        let title: String?
        let rows: [ShoppingActivityItem]
        let listCount: Int
    }

    private func snapshot(of scope: ShoppingActivityScope, in space: Space) throws -> Snapshot {
        let items = try ShoppingActivityState.openItems(scope: scope, in: space, service: shopping, pending: pending)
        return Snapshot(title: ShoppingActivityState.title(scope: scope, in: space, items: items, locations: locations,
                                                           locale: locale),
                        rows: ShoppingActivityState.rows(for: items, locale: locale),
                        listCount: ShoppingActivityState.listCount(of: items))
    }
}
