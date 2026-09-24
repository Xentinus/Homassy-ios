import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("StorageLocationsModel")
struct StorageLocationsModelTests {
    func seeded() throws -> (ServiceTestEnvironment, StorageLocationService, PendingDeletions) {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        try service.create(in: env.personal, name: "Fridge", color: .blue, isFreezer: false)
        try service.create(in: env.personal, name: "Pantry", color: .orange, isFreezer: false)
        try service.create(in: env.personal, name: "Freezer", color: .teal, isFreezer: true)
        return (env, service, PendingDeletions())
    }

    @Test func reloadBuildsRowsWithCounts() async throws {
        let (env, service, pending) = try seeded()
        let milk = try await env.makeProduct("Milk")
        try env.makeItem(milk, location: try service.location(named: "Fridge", in: env.personal))
        let model = StorageLocationsModel(service: service, space: env.personal, pending: pending)
        model.reload()
        #expect(model.rows.map(\.name) == ["Fridge", "Pantry", "Freezer"])
        #expect(model.rows[0].itemCount == 1)
        #expect(model.rows[0].color == .blue)
        #expect(model.rows[2].isFreezer)
        #expect(model.canEdit)
    }

    @Test func deleteHidesUntilCommitAndRevertBringsItBack() throws {
        let (env, service, pending) = try seeded()
        let model = StorageLocationsModel(service: service, space: env.personal, pending: pending)
        model.reload()
        let action = try #require(model.delete(model.visibleRows[1]))
        #expect(model.visibleRows.map(\.name) == ["Fridge", "Freezer"])
        action.revert()
        #expect(model.visibleRows.map(\.name) == ["Fridge", "Pantry", "Freezer"])

        let again = try #require(model.delete(model.visibleRows[1]))
        try again.commit()
        model.reload()
        #expect(model.rows.map(\.name) == ["Fridge", "Freezer"])
    }

    @Test func moveKeepsHiddenRowsAtTheEnd() throws {
        let (env, service, pending) = try seeded()
        let model = StorageLocationsModel(service: service, space: env.personal, pending: pending)
        model.reload()
        _ = model.delete(model.visibleRows[0])                     // hide Fridge
        model.move(fromOffsets: IndexSet([1]), toOffset: 0)        // Freezer above Pantry
        #expect(model.visibleRows.map(\.name) == ["Freezer", "Pantry"])
        #expect(try service.locations(in: env.personal).map(\.name) == ["Freezer", "Pantry", "Fridge"])
    }

    @Test func readOnlyDeleteReportsError() throws {
        let (env, _, pending) = try seeded()
        let readOnly = env.storageService(canEdit: { _ in false })
        let model = StorageLocationsModel(service: readOnly, space: env.personal, pending: pending)
        model.reload()
        #expect(!model.canEdit)
        #expect(model.delete(model.visibleRows[0]) == nil)
        #expect(model.errorMessage == ServiceError.readOnlySpace.errorDescription)
        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @Test func formCreatesAndEdits() throws {
        let (env, service, _) = try seeded()
        let create = StorageLocationFormModel(mode: .create(env.personal), service: service)
        #expect(!create.canSave)
        create.name = "Cellar"
        create.color = .green
        create.isFreezer = true
        #expect(create.canSave && !create.isEditing)
        #expect(create.save())
        let cellar = try #require(try service.location(named: "Cellar", in: env.personal))
        #expect(cellar.storageColor == .green && cellar.isFreezer)

        let edit = StorageLocationFormModel(mode: .edit(cellar), service: service)
        #expect(edit.isEditing && edit.name == "Cellar" && edit.color == .green)
        edit.name = "   "
        #expect(!edit.save())
        #expect(edit.errorMessage == ServiceError.nameRequired.errorDescription)
        edit.name = "Basement"
        edit.color = nil
        #expect(edit.save())
        #expect(cellar.name == "Basement" && cellar.color == nil)
    }
}
