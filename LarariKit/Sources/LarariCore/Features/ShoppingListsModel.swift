import Foundation
import Observation

@MainActor
@Observable
public final class ShoppingListsModel {
    public struct Summary: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let color: String?
        /// Items still to buy.
        public let remaining: Int
    }

    public let space: Space
    public private(set) var summaries: [Summary] = []
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private var lists: [UUID: ShoppingList] = [:]

    public init(service: ShoppingService, space: Space) {
        self.service = service
        self.space = space
    }

    public func reload() {
        do {
            let all = try service.lists(in: space)
            lists = Dictionary(all.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
            summaries = try all.map { list in
                Summary(id: list.publicId, name: list.name, color: list.color,
                        remaining: try service.unpurchasedItems(in: list).count)
            }
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
    }

    public func list(for id: UUID) -> ShoppingList? { lists[id] }

    @discardableResult
    public func createList(name: String, color: String?) -> Bool {
        perform { _ = try service.createList(name: name, color: color, in: space) }
    }

    @discardableResult
    public func updateList(_ id: UUID, name: String, color: String?) -> Bool {
        guard let list = lists[id] else { return false }
        return perform { try service.updateList(list, name: name, color: color) }
    }

    public func delete(_ id: UUID) {
        guard let list = lists[id] else { return }
        perform { try service.deleteList(list) }
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let ordered = Reordering.move(summaries.compactMap { lists[$0.id] }, fromOffsets: source, toOffset: destination)
        perform { try service.reorderLists(ordered) }
    }

    public func dismissError() { errorMessage = nil }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        defer { reload() }
        do {
            try work()
            return true
        } catch {
            errorMessage = FeatureError.message(for: error)
            return false
        }
    }
}
