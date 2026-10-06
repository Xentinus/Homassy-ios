import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("NotificationScheduler, BadgeCounter, coordinator")
struct NotificationSchedulerTests {
    static let en = Locale(identifier: "en_US")

    func planned(_ ids: [String]) -> [PlannedNotification] {
        ids.map { PlannedNotification(identifier: $0, fireDate: .now, dateComponents: DateComponents(), title: "t", body: "b") }
    }

    @Test func rescheduleReplacesOnlyItsOwnRequests() async {
        let center = FakeNotificationCenter(foreign: ["shopping-reminder-1", "backup-reminder"])
        await center.seedOwn(["daily-2020-01-01", "weekly-2020-01-06"])
        let scheduler = NotificationScheduler(center: center)
        await scheduler.reschedule(planned(["daily-2026-09-25", "weekly-2026-09-28"]))
        #expect(await center.identifiers == ["shopping-reminder-1", "backup-reminder", "daily-2026-09-25", "weekly-2026-09-28"])
        #expect(await center.removed.sorted() == ["daily-2020-01-01", "weekly-2020-01-06"])
    }

    @Test("Other features' requests count against the 64 limit")
    func respectsTheSystemCap() async {
        let center = FakeNotificationCenter(foreign: (0..<60).map { "other-\($0)" })
        let scheduler = NotificationScheduler(center: center)
        let added = await scheduler.reschedule(planned((1...10).map { String(format: "daily-2026-10-%02d", $0) }))
        #expect(added.map(\.identifier) == ["daily-2026-10-01", "daily-2026-10-02", "daily-2026-10-03", "daily-2026-10-04"])
        #expect(await center.identifiers.count == 64)
    }

    @Test func badgeCountsAttentionItemsAcrossSpaces() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk")
        let soap = try await env.makeProduct("Soap", in: home)
        try env.stock(milk, 1, expiresInDays: -3)          // expired
        try env.stock(milk, 1, expiresInDays: 0)           // critical
        try env.stock(milk, 1, expiresInDays: 14)          // soon
        try env.stock(milk, 1, expiresInDays: 15)          // ok
        try env.stock(milk, 1)                             // none
        try env.stock(soap, 1, expiresInDays: 2)           // other space, critical
        let finished = try env.stock(milk, 1, expiresInDays: 1)
        try env.inventoryService().markUsedUp(finished)    // consumed items never count
        #expect(try BadgeCounter.count(in: env.context, now: ServiceTestEnvironment.fixedNow,
                                       calendar: ServiceTestEnvironment.budapest) == 4)
    }

    @Test func snapshotsCoverTheHorizonPlusOneWeek() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        for offset in [-1, 0, 13, 20, 21, 30] { try env.stock(milk, 1, expiresInDays: offset) }
        let snapshots = try BadgeCounter.snapshots(in: env.context, now: ServiceTestEnvironment.fixedNow,
                                                   calendar: ServiceTestEnvironment.budapest)
        #expect(snapshots.map(\.expiresAt).sorted() == [env.day(0), env.day(13), env.day(20)])
        #expect(snapshots.allSatisfy { $0.name == "Milk" && $0.spaceName == env.personal.name })
    }

    @Test("500 items end to end: at most 64 pending, badge set")
    func fiveHundredItemsEndToEnd() async throws {
        let env = try ServiceTestEnvironment()
        var products: [Product] = []
        for index in 0..<25 { products.append(try await env.makeProduct("Product \(index)")) }
        for index in 0..<500 {
            try env.inventoryService().addStock(product: products[index % 25], quantity: 1, unit: .piece,
                                                expiresAt: env.day(index % 40 - 5), purchasedAt: nil, price: nil,
                                                currency: nil, storageLocation: nil, shoppingLocation: nil)
        }
        let center = FakeNotificationCenter(foreign: ["other"])
        let coordinator = ExpiryNotificationCoordinator(context: env.context, center: center,
                                                        calendar: ServiceTestEnvironment.budapest, locale: Self.en,
                                                        debounce: .zero, now: { ServiceTestEnvironment.fixedNow })
        await coordinator.refresh()
        #expect(await center.identifiers.count <= NotificationPlanner.maxPending)
        #expect(await center.pending.count == coordinator.lastPlan.count)
        #expect(!coordinator.lastPlan.isEmpty)
        let expected = try BadgeCounter.count(in: env.context, now: ServiceTestEnvironment.fixedNow,
                                              calendar: ServiceTestEnvironment.budapest)
        #expect(await center.badge == expected)
        #expect(coordinator.lastBadgeCount == expected)
        #expect(expected == (0..<500).filter { $0 % 40 - 5 <= 14 }.count)
    }

    @Test("A burst of triggers reschedules once")
    func debounce() async throws {
        let env = try ServiceTestEnvironment()
        try env.stock(try await env.makeProduct("Milk"), 1, expiresInDays: 2)
        let center = FakeNotificationCenter()
        let coordinator = ExpiryNotificationCoordinator(context: env.context, center: center,
                                                        calendar: ServiceTestEnvironment.budapest, locale: Self.en,
                                                        debounce: .milliseconds(50), now: { ServiceTestEnvironment.fixedNow })
        coordinator.scheduleRefresh(.localSave)
        coordinator.scheduleRefresh(.localSave)
        coordinator.scheduleRefresh(.remoteChange)
        await coordinator.pendingRefresh?.value
        #expect(coordinator.lastTrigger == .remoteChange)
        #expect(await center.addCount == coordinator.lastPlan.count)
        #expect(await center.badge == 1)
    }
}

