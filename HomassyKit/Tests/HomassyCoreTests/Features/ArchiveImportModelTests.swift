import Foundation
import Testing
@testable import HomassyCore

@MainActor
final class CallRecorder {
    var calls = 0
}

@MainActor
@Suite("Archive import model")
struct ArchiveImportModelTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    private func model(prepare: @escaping @MainActor () throws -> Void = {}) -> ArchiveImportModel {
        ArchiveImportModel(importer: stack.importer(), spaceStore: stack.spaceStore, prepare: prepare)
    }

    @Test func loadShowsThePreviewAndSuggestsTheArchiveName() throws {
        _ = stack.makeSpace(name: "Nyaraló")
        try stack.context.save()
        let model = model()
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))

        #expect(model.phase == .ready)
        #expect(model.choice == .newSpace)
        #expect(model.newSpaceName == "Otthon")
        #expect(model.preview?.counts(for: .products) == EntityImportCounts(toCreate: 2))
        #expect(model.targets.map(\.name) == ["Nyaraló"])
        #expect(model.canConfirm)
        #expect(model.preview?.counts(for: .inventoryEvents) == EntityImportCounts(toCreate: 4))
    }

    @Test func choosingAMergeTargetRecomputesThePreview() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        try stack.importer().importArchive(url: url, mode: .merge(into: home))

        let model = model()
        model.load(url: url)
        model.choice = .merge(home.publicId)

        #expect(model.preview?.isMerge == true)
        #expect(model.preview?.counts(for: .products) == EntityImportCounts(unchanged: 2))
        #expect(model.canConfirm)
        model.choice = .newSpace
        #expect(model.preview?.isMerge == false)
    }

    @Test func confirmAsNewSpaceImportsAndFinishes() throws {
        let recorder = CallRecorder()
        let model = model(prepare: { recorder.calls += 1 })
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        model.newSpaceName = "Új otthon"

        let space = try #require(model.confirm())
        #expect(recorder.calls == 1)
        #expect(space.name == "Új otthon")
        #expect(model.phase == .finished)
        #expect(model.importedSpace == space)
    }

    @Test func confirmMergeImportsIntoTheTarget() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        let model = model()
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        model.choice = .merge(home.publicId)

        #expect(model.confirm() == home)
        #expect(try stack.fetch(Product.self, "space == %@", home).count == 2)
    }

    @Test func blankNameCannotBeConfirmed() throws {
        let model = model()
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        model.newSpaceName = "   "
        #expect(!model.canConfirm)
        #expect(model.confirm() == nil)
        #expect(model.phase == .ready)
        #expect(try stack.spaceCount() == 0)
    }

    @Test func prepareFailureIsShownAndNothingIsImported() throws {
        let model = model(prepare: { throw ArchiveError.unsavedChanges })
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        #expect(model.confirm() == nil)
        #expect(model.phase == .failed(ArchiveError.unsavedChanges.errorDescription ?? ""))
        #expect(try stack.spaceCount() == 0)
    }

    @Test func unreadableFileFails() throws {
        let url = stack.temporaryURL()
        try Data("garbage".utf8).write(to: url)
        let model = model()
        model.load(url: url)
        #expect(model.phase == .failed(ArchiveError.corrupted("").errorDescription ?? ""))
        #expect(!model.canConfirm)
    }
}

@MainActor
@Suite("Archive import model selection")
struct ArchiveImportModelSelectionTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    private func loadedModel() throws -> ArchiveImportModel {
        let model = ArchiveImportModel(importer: stack.importer(), spaceStore: stack.spaceStore)
        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        return model
    }

    @Test func everythingIsSelectedAfterLoading() throws {
        let model = try loadedModel()
        #expect(model.groups == Set(ArchiveSelection.Group.allCases))
        #expect(model.pickedIDs(for: .products) == [ArchiveSamples.milkID, ArchiveSamples.flourID])
        #expect(model.options(for: .products).map(\.title) == ["Liszt", "Tej"])
        let milk = try #require(model.options(for: .products).first { $0.title == "Tej" })
        #expect(milk.detail == .text("Mizo · Tejtermék"))
        #expect(milk.keywords.contains("5998200110039"))
        #expect(model.options(for: .members).map(\.title) == ["Anna", "Béla"])
        #expect(model.options(for: .storageLocations).first?.detail == nil)
        #expect(model.options(for: .shoppingLists).first?.detail == .items(2))
        #expect(model.options(for: .stock).isEmpty)
        #expect(model.selection == .everything)
        #expect(model.isStockAvailable)
    }

    @Test func turningGroupsOffRecomputesThePreview() throws {
        let model = try loadedModel()
        model.setGroup(.stock, isOn: false)
        model.setGroup(.storageLocations, isOn: false)
        #expect(model.preview?.counts(for: .inventoryItems) == EntityImportCounts())
        #expect(model.preview?.counts(for: .storageLocations) == EntityImportCounts())
        #expect(model.preview?.counts(for: .products) == EntityImportCounts(toCreate: 2))

        model.setGroup(.stock, isOn: true)
        #expect(model.preview?.counts(for: .storageLocations) == EntityImportCounts(toCreate: 1))
        #expect(model.preview?.autoIncluded == [.storageLocations: 1])
    }

    @Test func pickingProductsNarrowsTheSelection() throws {
        let model = try loadedModel()
        model.setRecords([ArchiveSamples.flourID], in: .products, selected: false)
        #expect(model.selection.productIDs == [ArchiveSamples.milkID])
        #expect(model.preview?.counts(for: .products) == EntityImportCounts(toCreate: 1))
        #expect(model.preview?.counts(for: .inventoryItems) == EntityImportCounts(toCreate: 1))
    }

    @Test func pickingMembersNarrowsTheSelection() throws {
        let model = try loadedModel()
        model.setRecords([ArchiveSamples.ownerMemberID], in: .members, selected: false)
        #expect(model.selection.picks[.members] == [ArchiveSamples.annaMemberID])
        #expect(model.preview?.counts(for: .members) == EntityImportCounts(toCreate: 1))
    }

    @Test func unpickedStorageNeededByStockIsAutomatic() throws {
        let model = try loadedModel()
        model.setRecords([ArchiveSamples.fridgeID], in: .storageLocations, selected: false)
        #expect(!model.groups.contains(.storageLocations))
        #expect(model.preview?.autoIncluded == [.storageLocations: 1])
    }

    @Test func deselectingTheLastProductTurnsProductsAndStockOff() throws {
        let model = try loadedModel()
        model.setRecords([ArchiveSamples.milkID, ArchiveSamples.flourID], in: .products, selected: false)
        #expect(!model.groups.contains(.products))
        #expect(!model.isStockAvailable)
        #expect(model.preview?.counts(for: .inventoryItems) == EntityImportCounts())
        #expect(model.preview?.unlinkedListItems == 1)

        model.setRecords([ArchiveSamples.milkID], in: .products, selected: true)
        #expect(model.groups.contains(.products))
        #expect(model.isStockAvailable)
    }

    @Test func turningAGroupBackOnPicksAllOfIt() throws {
        let model = try loadedModel()
        model.setRecords([ArchiveSamples.milkID, ArchiveSamples.flourID], in: .products, selected: false)
        model.setGroup(.products, isOn: true)
        #expect(model.pickedIDs(for: .products).count == 2)
        model.setRecords([ArchiveSamples.weeklyListID], in: .shoppingLists, selected: false)
        model.setGroup(.shoppingLists, isOn: true)
        #expect(model.pickedIDs(for: .shoppingLists) == [ArchiveSamples.weeklyListID])
    }

    @Test func aGroupThatIsOffHasNothingTicked() throws {
        let model = try loadedModel()
        model.setGroup(.members, isOn: false)
        #expect(model.pickedIDs(for: .members).isEmpty)
        model.setRecords([ArchiveSamples.annaMemberID], in: .members, selected: true)
        #expect(model.groups.contains(.members))
        #expect(model.pickedIDs(for: .members) == [ArchiveSamples.annaMemberID])
        model.setGroup(.members, isOn: false)
        model.setGroup(.members, isOn: true)
        #expect(model.pickedIDs(for: .members) == [ArchiveSamples.annaMemberID])
    }

    @Test func emptySelectionCannotBeConfirmed() throws {
        let model = try loadedModel()
        for group in ArchiveSelection.Group.allCases { model.setGroup(group, isOn: false) }
        #expect(model.isSelectionEmpty)
        #expect(!model.canConfirm)
        #expect(model.confirm() == nil)
        #expect(try stack.spaceCount() == 0)
    }

    @Test func confirmImportsOnlyTheSelection() throws {
        let model = try loadedModel()
        for group in ArchiveSelection.Group.allCases where group != .products { model.setGroup(group, isOn: false) }
        model.setRecords([ArchiveSamples.flourID], in: .products, selected: false)
        let space = try #require(model.confirm())
        #expect(try stack.fetch(Product.self, "space == %@", space).map(\.name) == ["Tej"])
        #expect(try stack.fetch(Member.self, "space == %@", space).isEmpty)
    }
}
