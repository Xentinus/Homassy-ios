import CoreData
import Testing
@testable import HomassyCore

@MainActor
struct ObjectGraphTests {
    @Test func collectsEveryObjectReachableFromTheSpaceButNotOtherSpaces() throws {
        let persistence = try PersistenceController(mode: .inMemory)
        let store = SpaceStore(persistence: persistence, sharing: FakeCloudSharing(persistence: persistence))
        let home = try SharingFixtures.insertSpace(named: "Home", into: persistence.privateStore, of: persistence, by: "_me")
        let other = try SharingFixtures.insertSpace(named: "Other", into: persistence.privateStore, of: persistence, by: "_me")
        let member = store.insert(Member.self, in: home, by: "_me")
        member.space = home
        let otherMember = store.insert(Member.self, in: other, by: "_me")
        otherMember.space = other
        try persistence.viewContext.save()

        let ids = ObjectGraph.objectIDs(reachableFrom: home)

        #expect(ids.contains(home.objectID))
        #expect(ids.contains(member.objectID))
        #expect(!ids.contains(other.objectID))
        #expect(!ids.contains(otherMember.objectID))
    }
}
