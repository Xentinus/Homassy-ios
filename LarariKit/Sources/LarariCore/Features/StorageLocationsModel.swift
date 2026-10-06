import CoreData
import Foundation
import Observation

public struct StorageLocationRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let color: StorageColor?
    public let isFreezer: Bool
    public let itemCount: Int
}

@MainActor
@Observable
public final class StorageLocationsModel {
    public let space: Space
    public private(set) var rows: [StorageLocationRow] = []
    public private(set) var errorMessage: String?

    private let service: StorageLocationService
    private let pending: PendingDeletions
    private var objects: [UUID: StorageLocation] = [:]

    public init(service: StorageLocationService, space: Space, pending: PendingDeletions) {
        self.service = service
        self.space = space
        self.pending = pending
    }

    public var visibleRows: [StorageLocationRow] { rows.filter { !pending.contains($0.id) } }
    public var canEdit: Bool { service.canEdit(space) }

    public func reload() {
        do {
            let locations = try service.locations(in: space)
            objects = Dictionary(locations.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
            rows = try locations.map {
                StorageLocationRow(id: $0.publicId, name: $0.name, color: $0.storageColor,
                                   isFreezer: $0.isFreezer, itemCount: try service.itemCount(in: $0))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func location(for id: UUID) -> StorageLocation? { objects[id] }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let visible = visibleRows.compactMap { objects[$0.id] }
        let hidden = rows.filter { pending.contains($0.id) }.compactMap { objects[$0.id] }
        do {
            try service.setOrder(Reordering.move(visible, fromOffsets: source, toOffset: destination) + hidden)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    public func delete(_ row: StorageLocationRow) -> UndoableAction? {
        guard let location = objects[row.id] else { return nil }
        do {
            return try service.deletion(of: location, pending: pending)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func dismissError() { errorMessage = nil }
}
