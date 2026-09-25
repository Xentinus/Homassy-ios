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
