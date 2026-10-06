import Foundation
import LarariShared
import Testing
@testable import LarariCore

@MainActor
@Suite("Shopping Live Activity routing")
struct ShoppingActivityRoutingTests {
    @Test func deepLinksMapOntoDestinations() {
        let space = UUID()
        #expect(AppDestination(LarariDeepLink.inventory(spaceID: space)) == .inventory(spaceID: space))
        #expect(AppDestination(LarariDeepLink.shoppingStore(spaceID: space, scope: .store(UUID())))
                == .shoppingByStore(spaceID: space))
        #expect(AppDestination(LarariDeepLink.shoppingStore(spaceID: space, scope: .chain("spar")))
                == .shoppingByStore(spaceID: space))
    }

    @Test func aDeletedSpaceFallsBackToTheCurrentShoppingHome() throws {
        let env = try ServiceTestEnvironment()
        let services = ServiceContainer(spaceStore: env.spaceStore, context: env.context,
                                        userRecordName: ServiceTestEnvironment.user)
        let personal = env.personal.publicId
        #expect(services.validated(.shoppingByStore(spaceID: personal)) == .shoppingByStore(spaceID: personal))
        #expect(services.validated(.shoppingByStore(spaceID: UUID())) == .shopping(spaceID: nil))
    }
}
