import Foundation
import Testing
@testable import HomassyShared

@Suite("HomassyDeepLink")
struct HomassyDeepLinkTests {
    let space = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let store = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let other = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    @Test func buildsStableURLs() {
        #expect(HomassyDeepLink.shoppingStore(spaceID: space, scope: .store(store)).url.absoluteString
                == "homassy://shopping?space=11111111-1111-1111-1111-111111111111&store=22222222-2222-2222-2222-222222222222")
        #expect(HomassyDeepLink.shoppingStore(spaceID: space, scope: .stores([store, other])).url.absoluteString
                == "homassy://shopping?space=11111111-1111-1111-1111-111111111111&stores=22222222-2222-2222-2222-222222222222,33333333-3333-3333-3333-333333333333")
        #expect(HomassyDeepLink.shoppingStore(spaceID: space, scope: .chain("tesco expressz")).url.absoluteString
                == "homassy://shopping?space=11111111-1111-1111-1111-111111111111&chain=tesco%20expressz")
        #expect(HomassyDeepLink.inventory(spaceID: space).url.absoluteString
                == "homassy://inventory?space=11111111-1111-1111-1111-111111111111")
        #expect(HomassyDeepLink.inventory(spaceID: nil).url.absoluteString == "homassy://inventory")
    }

    @Test func parsesWhatItBuilds() {
        let links: [HomassyDeepLink] = [.shoppingStore(spaceID: space, scope: .store(store)),
                                        .shoppingStore(spaceID: space, scope: .stores([store, other])),
                                        .shoppingStore(spaceID: space, scope: .chain("spar")),
                                        .shoppingStore(spaceID: space, scope: .chain("tesco expressz")),
                                        .inventory(spaceID: space), .inventory(spaceID: nil)]
        for link in links {
            #expect(HomassyDeepLink(url: link.url) == link)
        }
    }

    @Test func rejectsOtherLinks() {
        #expect(HomassyDeepLink(url: URL(string: "https://homassy.com/shopping")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://shopping?space=nope&store=nope")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://shopping?space=11111111-1111-1111-1111-111111111111")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://shopping?space=11111111-1111-1111-1111-111111111111&chain=")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://shopping?space=11111111-1111-1111-1111-111111111111&stores=nope")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://shopping?space=11111111-1111-1111-1111-111111111111&stores=22222222-2222-2222-2222-222222222222,x")!) == nil)
        #expect(HomassyDeepLink(url: URL(string: "homassy://settings")!) == nil)
        #expect(HomassyDeepLink(url: URL(fileURLWithPath: "/tmp/Heti.homassy")) == nil)   // archives go to the import router
    }
}
