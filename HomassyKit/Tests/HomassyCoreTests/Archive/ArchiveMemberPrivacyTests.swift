import CloudKit
import CoreData
import Foundation
import Testing
@testable import HomassyCore

/// P5-02a: members travel only with the household's owner, a non-owner export carries no one else's
/// photo, an import never shares, and a merge needs write access.
@MainActor
@Suite("Archive member privacy")
struct ArchiveMemberPrivacyTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    /// The sample archive with the importing user added as a member, owned by `_owner0001`.
    private func foreignArchiveWithMyMember() -> ArchiveContents {
        var contents = ArchiveSamples.sampleV1
        var mine = contents.data.members[0]
        mine.publicId = UUID()
        mine.userRecordName = stack.user
        mine.displayName = "Én"
        mine.colorSeed = stack.user
        mine.avatar = nil
        contents.data.members.append(mine)
        return contents
    }

    // MARK: Import

    @Test func anOwnerBringsEveryMemberAlong() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let preview = try stack.importer().preview(url: url)
        #expect(preview.counts(for: .members).toCreate == 2)
        #expect(preview.withheldMembers == 0)

        let space = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Másolat")).space
        #expect(try stack.fetch(Member.self, "space == %@", space).count == 2)
    }

    @Test func aNonOwnerBringsOnlyTheirOwnMember() throws {
        let url = try stack.writeArchive(foreignArchiveWithMyMember(), ownedBy: "_owner0001")
        let importer = stack.importer()

        let preview = try importer.preview(url: url)
        #expect(preview.counts(for: .members).toCreate == 1)
        #expect(preview.withheldMembers == 2)
        #expect(try importer.importable(importer.read(url: url).contents.data).members.map(\.userRecordName) == [stack.user])

        let space = try importer.importArchive(url: url, mode: .asNewSpace(name: "Másolat")).space
        let members = try stack.fetch(Member.self, "space == %@", space)
        #expect(members.map(\.userRecordName) == [stack.user])
        #expect(members.map(\.displayName) == ["Én"])
    }

    @Test func aNonOwnerWithoutOwnMemberBringsNoMembers() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1, ownedBy: "_owner0001")
        let preview = try stack.importer().preview(url: url)
        #expect(preview.counts(for: .members).total == 0)
        #expect(preview.withheldMembers == 2)
        #expect(preview.counts(for: .products).toCreate == 2)     // everything else still comes along
    }

    @Test func importingNeverSharesOrInvites() async throws {
        let cloud = FakeCloudSharing(persistence: stack.persistence)
        let spaceStore = SpaceStore(persistence: stack.persistence, sharing: cloud)
        let sharing = SharingService(persistence: stack.persistence, spaceStore: spaceStore, cloud: cloud,
                                     userRecordName: stack.user)
        let importer = ArchiveImporter(persistence: stack.persistence, spaceStore: spaceStore, userRecordName: stack.user)
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)

        let space = try importer.importArchive(url: url, mode: .asNewSpace(name: "Másolat")).space

        #expect(space.createdBy == stack.user)
        #expect(sharing.role(for: space) == .notShared)
        #expect(cloud.shareCallCount == 0)
        #expect(cloud.persistedShares.isEmpty)
    }

    // MARK: Merge permission

    @Test func mergingIntoAReadOnlySpaceIsRefused() throws {
        let readOnly = stack.makeSpace(name: "Csak olvasható")
        try stack.context.save()
        let importer = stack.importer(canEdit: { $0 !== readOnly })
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)

        #expect(!importer.canMerge(into: readOnly))
        #expect(throws: ServiceError.readOnlySpace) { _ = try importer.preview(url: url, mergeInto: readOnly) }
        #expect(throws: ServiceError.readOnlySpace) { _ = try importer.importArchive(url: url, mode: .merge(into: readOnly)) }
        #expect(try stack.count(Product.self) == 0)
    }

    @Test func mergeTargetsExcludeReadOnlySpaces() throws {
        let editable = stack.makeSpace(name: "Otthon")
        let readOnly = stack.makeSpace(name: "Csak olvasható")
        try stack.context.save()
        let model = ArchiveImportModel(importer: stack.importer(canEdit: { $0 !== readOnly }), spaceStore: stack.spaceStore)

        model.load(url: try stack.writeArchive(ArchiveSamples.sampleV1))

        #expect(model.targets.map(\.id) == [editable.publicId])
    }

    @Test func thePickerOffersOnlyImportableMembers() throws {
        let model = ArchiveImportModel(importer: stack.importer(), spaceStore: stack.spaceStore)
        model.load(url: try stack.writeArchive(foreignArchiveWithMyMember(), ownedBy: "_owner0001"))
        #expect(model.options(for: .members).map(\.title) == ["Én"])
        #expect(model.preview?.withheldMembers == 2)
    }

    // MARK: Export

    private func seedWithPhotos() throws -> (space: Space, mine: Member, other: Member) {
        let space = stack.makeSpace(name: "Otthon")
        let mine = stack.insert(Member.self, in: space)
        mine.space = space
        mine.userRecordName = stack.user
        mine.displayName = "Én"
        mine.avatar = Data(repeating: 0x11, count: 512)
        let other = stack.insert(Member.self, in: space)
        other.space = space
        other.userRecordName = "_anna"
        other.displayName = "Anna"
        other.avatar = Data(repeating: 0x22, count: 512)
        try stack.context.save()
        return (space, mine, other)
    }

    @Test func aNonOwnerExportLeavesOtherMembersPhotosOut() throws {
        let seeded = try seedWithPhotos()
        let exporter = ArchiveExporter(context: stack.context, userRecordName: stack.user, ownsSpace: { _ in false })

        let loaded = try exporter.snapshot(of: seeded.space)
        let members = Dictionary(uniqueKeysWithValues: loaded.contents.data.members.map { ($0.userRecordName, $0) })

        #expect(members["_anna"]?.displayName == "Anna")
        #expect(members["_anna"]?.avatar == nil)
        #expect(members[stack.user]?.avatar != nil)
        #expect(loaded.images.count == 1)
    }

    @Test func anOwnerExportKeepsEveryPhoto() throws {
        let seeded = try seedWithPhotos()
        let exporter = ArchiveExporter(context: stack.context, userRecordName: stack.user, ownsSpace: { _ in true })
        let loaded = try exporter.snapshot(of: seeded.space)
        #expect(loaded.contents.data.members.allSatisfy { $0.avatar != nil })
        #expect(loaded.images.count == 2)
    }

    @Test func archiveServicesTreatOnlyPrivateStoreSpacesAsOwned() throws {
        let services = ArchiveServices(persistence: stack.persistence, spaceStore: stack.spaceStore, userRecordName: stack.user)
        let owned = stack.makeSpace(name: "Enyém")
        let joined = Space(context: stack.context)
        stack.context.assign(joined, to: stack.persistence.sharedStore)
        joined.publicId = UUID()
        joined.name = "Övék"
        joined.kind = .household
        joined.stamp(by: "_friend")
        try stack.context.save()

        #expect(services.ownsSpace(owned))
        #expect(!services.ownsSpace(joined))
    }
}
