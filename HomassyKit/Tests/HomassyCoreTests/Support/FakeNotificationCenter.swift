import Foundation
@testable import HomassyCore

actor FakeNotificationCenter: NotificationCentering {
    private(set) var pending: [String: PlannedNotification] = [:]
    private(set) var foreign: Set<String>
    private(set) var badge: Int?
    private(set) var addCount = 0
    private(set) var removed: [String] = []

    private(set) var locationPending: [String: PlannedStoreReminder] = [:]

    func seedLocation(_ identifiers: [String]) {
        for id in identifiers {
            locationPending[id] = PlannedStoreReminder(identifier: id, title: "old", body: "old",
                                                       center: Coordinate(latitude: 0, longitude: 0), radius: 150)
        }
    }

    func addLocation(_ reminder: PlannedStoreReminder) async throws {
        addCount += 1
        locationPending[reminder.identifier] = reminder
    }

    init(foreign: [String] = []) {
        self.foreign = Set(foreign)
    }

    var identifiers: Set<String> { Set(pending.keys).union(foreign).union(locationPending.keys) }

    func seedOwn(_ identifiers: [String]) {
        for id in identifiers {
            pending[id] = PlannedNotification(identifier: id, fireDate: .distantPast, dateComponents: DateComponents(),
                                              title: "old", body: "old")
        }
    }

    func pendingRequestIdentifiers() async -> [String] { Array(identifiers).sorted() }

    func add(_ notification: PlannedNotification) async throws {
        addCount += 1
        pending[notification.identifier] = notification
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        removed += identifiers
        for id in identifiers {
            pending[id] = nil
            locationPending[id] = nil
            foreign.remove(id)
        }
    }

    func setBadgeCount(_ count: Int) async throws { badge = count }
}
