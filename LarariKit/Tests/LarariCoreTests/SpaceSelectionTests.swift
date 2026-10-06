import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("SpaceSelection")
struct SpaceSelectionTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "SpaceSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func startsEmpty() {
        #expect(SpaceSelection(defaults: freshDefaults()).selectedSpaceID == nil)
    }

    @Test func persistsTheSelectionUnderSelectedSpaceID() {
        let defaults = freshDefaults()
        let id = UUID()
        SpaceSelection(defaults: defaults).selectedSpaceID = id

        #expect(defaults.string(forKey: "selectedSpaceID") == id.uuidString)
        #expect(SpaceSelection(defaults: defaults).selectedSpaceID == id)
    }

    @Test func clearingRemovesTheStoredValue() {
        let defaults = freshDefaults()
        let selection = SpaceSelection(defaults: defaults)
        selection.selectedSpaceID = UUID()
        selection.selectedSpaceID = nil

        #expect(defaults.object(forKey: "selectedSpaceID") == nil)
    }

    @Test func ignoresAGarbageStoredValue() {
        let defaults = freshDefaults()
        defaults.set("not-a-uuid", forKey: "selectedSpaceID")
        #expect(SpaceSelection(defaults: defaults).selectedSpaceID == nil)
    }

    @Test func resolvesTheSelectedSpace() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let flat = f.makeSpace("Flat", sortOrder: 1)
        try f.context.save()
        let selection = SpaceSelection(defaults: freshDefaults())
        selection.select(flat)

        let spaces = try f.store.allSpaces()
        #expect(selection.resolve(in: spaces)?.objectID == flat.objectID)
        #expect(selection.resolve(in: spaces)?.objectID != personal.objectID)
    }

    @Test func fallsBackToPersonalWhenTheSelectedSpaceIsMissing() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        _ = f.makeSpace("Flat", sortOrder: 1)
        try f.context.save()
        let selection = SpaceSelection(defaults: freshDefaults())
        let goneID = UUID()
        selection.selectedSpaceID = goneID

        #expect(selection.resolve(in: try f.store.allSpaces())?.objectID == personal.objectID)
        #expect(selection.selectedSpaceID == goneID)      // kept, so the space is picked again when it syncs back
    }

    @Test func fallsBackToPersonalWhenNothingIsSelected() throws {
        let f = try SpaceFixture()
        _ = f.makeSpace("Flat", sortOrder: 0)
        try f.context.save()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let selection = SpaceSelection(defaults: freshDefaults())

        #expect(selection.resolve(in: try f.store.allSpaces())?.objectID == personal.objectID)
    }

    @Test func fallsBackToTheFirstSpaceWithoutPersonal() throws {
        let f = try SpaceFixture()
        let flat = f.makeSpace("Flat", sortOrder: 0)
        _ = f.makeSpace("Cabin", sortOrder: 1)
        try f.context.save()
        let selection = SpaceSelection(defaults: freshDefaults())

        #expect(selection.resolve(in: try f.store.allSpaces())?.objectID == flat.objectID)
    }

    @Test func resolvesNothingFromNoSpaces() {
        #expect(SpaceSelection(defaults: freshDefaults()).resolve(in: []) == nil)
    }

    // MARK: Per window (N-03)

    @Test func aRestoredWindowStartsWithItsOwnSpace() {
        let defaults = freshDefaults()
        let lastUsed = UUID()
        let own = UUID()
        defaults.set(lastUsed.uuidString, forKey: SpaceSelection.defaultsKey)

        #expect(SpaceSelection(defaults: defaults, restoredID: own).selectedSpaceID == own)
    }

    @Test func aNewWindowStartsFromTheLastUsedSpace() {
        let defaults = freshDefaults()
        let lastUsed = UUID()
        defaults.set(lastUsed.uuidString, forKey: SpaceSelection.defaultsKey)

        #expect(SpaceSelection(defaults: defaults, restoredID: nil).selectedSpaceID == lastUsed)
    }

    @Test func windowsChooseIndependentlyAndTheLastChoiceSeedsTheNextWindow() {
        let defaults = freshDefaults()
        let left = SpaceSelection(defaults: defaults, restoredID: UUID())
        let rightID = UUID()
        let right = SpaceSelection(defaults: defaults, restoredID: rightID)

        let picked = UUID()
        left.selectedSpaceID = picked

        #expect(right.selectedSpaceID == rightID)             // the other window keeps its space
        #expect(defaults.string(forKey: SpaceSelection.defaultsKey) == picked.uuidString)
        #expect(SpaceSelection(defaults: defaults).selectedSpaceID == picked)
    }

    @Test func restoringDoesNotChangeTheLastUsedSpace() {
        let defaults = freshDefaults()
        let lastUsed = UUID()
        defaults.set(lastUsed.uuidString, forKey: SpaceSelection.defaultsKey)
        let selection = SpaceSelection(defaults: defaults, restoredID: UUID())

        let shown = UUID()
        selection.restore(shown)

        #expect(selection.selectedSpaceID == shown)
        #expect(defaults.string(forKey: SpaceSelection.defaultsKey) == lastUsed.uuidString)
        selection.restore(nil)
        #expect(selection.selectedSpaceID == nil)
        #expect(defaults.string(forKey: SpaceSelection.defaultsKey) == lastUsed.uuidString)
    }

    @Test func aRestoredWindowResolvesItsOwnSpace() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let flat = f.makeSpace("Flat", sortOrder: 1)
        try f.context.save()
        let defaults = freshDefaults()
        defaults.set(personal.publicId.uuidString, forKey: SpaceSelection.defaultsKey)

        let window = SpaceSelection(defaults: defaults, restoredID: flat.publicId)
        #expect(window.resolve(in: try f.store.allSpaces())?.objectID == flat.objectID)
    }
}
