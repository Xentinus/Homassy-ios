import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("PendingDeletions")
struct PendingDeletionsTests {
    @Test func revertRestoresWithoutTouchingTheStore() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let pending = PendingDeletions()
        let action = try env.productService().deletion(of: milk, pending: pending)
        #expect(pending.contains(milk.publicId))
        #expect(action.title == UndoTitle.removed("Milk"))
        #expect(!env.context.hasChanges)

        action.revert()
        #expect(!pending.contains(milk.publicId))
        #expect(try env.count(Product.self) == 1)
    }

    @Test func commitDeletesAndSaves() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let pending = PendingDeletions()
        let action = try env.productService().deletion(of: milk, pending: pending)
        try action.commit()
        #expect(try env.count(Product.self) == 0)
        #expect(!env.context.hasChanges)
        #expect(pending.ids.isEmpty)
    }

    @Test func commitAfterRemoteDeletionIsANoOp() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let pending = PendingDeletions()
        let action = try env.productService().deletion(of: milk, pending: pending)
        env.context.delete(milk)
        try env.context.save()
        try action.commit()
        #expect(pending.ids.isEmpty)
    }
}
