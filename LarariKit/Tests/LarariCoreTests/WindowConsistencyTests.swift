import CoreData
import Foundation
import Testing
@testable import LarariCore

/// N-03: every iPad window works on the one shared view context, so a change made in one window is what every
/// other window's model reads on its next reload. The views reload on `NSManagedObjectContextObjectsDidChange`
/// (`ShoppingHomeView`, `InventoryView`, `SearchView`), and these tests do the same.
@MainActor
@Suite("Window consistency")
struct WindowConsistencyTests {
    let stack: ShoppingTestStack
    let defaults: UserDefaults

    init() throws {
        stack = try ShoppingTestStack()
        defaults = try #require(UserDefaults(suiteName: "test.windowConsistency.\(UUID().uuidString)"))
    }

    private func overview(queue: UndoQueue, pinnedListID: UUID? = nil) -> ShoppingOverviewModel {
        ShoppingOverviewModel(service: stack.service, space: stack.space, undoQueue: queue, pending: stack.pending,
                              preferences: ShoppingHomePreferences(defaults: defaults), distance: { _ in nil },
                              storeTitle: { _ in nil }, pinnedListID: pinnedListID)
    }

    private func names(_ model: ShoppingOverviewModel) -> [String] { model.sections.flatMap(\.rows).map(\.name) }

    /// Reloads like the views do, until the returned token is removed.
    private func reloadOnChange(_ reload: @escaping @MainActor @Sendable () -> Void) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                                               object: stack.context, queue: nil) { _ in
            MainActor.assumeIsolated { reload() }
        }
    }

    /// A list window opens its list whatever space its window happens to show.
    @Test func aListOpensByPublicIdInAnySpace() throws {
        let other = try stack.makeOtherSpace()
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: other)

        #expect(try stack.service.list(publicId: weekly.publicId) == weekly)
        #expect(try stack.service.list(publicId: party.publicId) == party)
        #expect(try stack.service.list(publicId: UUID()) == nil)

        let partyID = party.publicId                          // a deleted object's attributes are gone
        try stack.service.deleteList(party)
        #expect(try stack.service.list(publicId: partyID) == nil)
    }

    /// Window A shows one list, window B the whole Shopping home; an item added in A shows in B without extra code.
    @Test func aChangeInOneWindowReachesTheOtherWindowsModels() throws {
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.createList(name: "Drogéria", in: stack.space)
        let registry = UndoQueueRegistry()
        let listWindow = overview(queue: registry.makeQueue(), pinnedListID: weekly.publicId)
        let homeWindow = overview(queue: registry.makeQueue())
        #expect(homeWindow.chips.first { $0.name == "Heti" }?.remaining == 0)

        let token = reloadOnChange { listWindow.reload(); homeWindow.reload() }
        defer { NotificationCenter.default.removeObserver(token) }

        try stack.service.addItem(to: weekly, customName: "Alma")
        stack.context.processPendingChanges()

        #expect(names(listWindow) == ["Alma"])
        #expect(homeWindow.chips.first { $0.name == "Heti" }?.remaining == 1)
    }

    /// Two windows on the same list: a delete hides the item in both (shared `PendingDeletions`), but the toast
    /// and the undo belong to the window where the delete happened (D2 = A).
    @Test func aDeleteHidesTheItemInEveryWindowAndOnlyItsWindowCanUndoIt() throws {
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let apple = try stack.service.addItem(to: weekly, customName: "Alma")
        let registry = UndoQueueRegistry()
        let leftQueue = registry.makeQueue()
        let rightQueue = registry.makeQueue()
        let left = overview(queue: leftQueue, pinnedListID: weekly.publicId)
        let right = overview(queue: rightQueue)

        left.delete(apple.publicId)

        #expect(names(left).isEmpty)
        #expect(names(right).isEmpty)
        #expect(leftQueue.pending.count == 1)
        #expect(rightQueue.pending.isEmpty)

        leftQueue.undoAll()

        #expect(names(right) == ["Alma"])
        #expect(names(left) == ["Alma"])
    }

    /// A list window shows its list without the strip, and never touches the main window's remembered filter.
    @Test func aListWindowIsPinnedAndLeavesTheRememberedFilterAlone() throws {
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let drugstore = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: weekly, customName: "Alma")
        try stack.service.addItem(to: drugstore, customName: "Szappan")

        let home = overview(queue: UndoQueue())
        home.filter = drugstore.publicId
        let window = overview(queue: UndoQueue(), pinnedListID: weekly.publicId)

        #expect(window.filter == weekly.publicId)
        #expect(!window.showsStrip)
        #expect(names(window) == ["Alma"])
        window.filter = nil
        #expect(window.filter == weekly.publicId)
        #expect(ShoppingHomePreferences(defaults: defaults).filter(for: stack.space.publicId) == drugstore.publicId)
        #expect(!window.isPinnedListMissing)
    }

    /// The list of a list window is deleted in another window: the window says so instead of showing stale data.
    @Test func aDeletedListLeavesItsWindowEmpty() throws {
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: weekly, customName: "Alma")
        let weeklyID = weekly.publicId
        let window = overview(queue: UndoQueue(), pinnedListID: weeklyID)

        try stack.service.deleteList(weekly)
        window.reload()

        #expect(window.isPinnedListMissing)
        #expect(names(window).isEmpty)
        #expect(window.filter == weeklyID)
    }
}
