import Foundation
import Testing
@testable import LarariShared

@Suite("LarariDeepLink")
struct LarariDeepLinkTests {
    let space = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let store = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let other = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    @Test func buildsStableURLs() {
        #expect(LarariDeepLink.shoppingStore(spaceID: space, scope: .store(store)).url.absoluteString
                == "larari://shopping?space=11111111-1111-1111-1111-111111111111&store=22222222-2222-2222-2222-222222222222")
        #expect(LarariDeepLink.shoppingStore(spaceID: space, scope: .stores([store, other])).url.absoluteString
                == "larari://shopping?space=11111111-1111-1111-1111-111111111111&stores=22222222-2222-2222-2222-222222222222,33333333-3333-3333-3333-333333333333")
        #expect(LarariDeepLink.shoppingStore(spaceID: space, scope: .chain("tesco expressz")).url.absoluteString
                == "larari://shopping?space=11111111-1111-1111-1111-111111111111&chain=tesco%20expressz")
        #expect(LarariDeepLink.inventory(spaceID: space).url.absoluteString
                == "larari://inventory?space=11111111-1111-1111-1111-111111111111")
        #expect(LarariDeepLink.inventory(spaceID: nil).url.absoluteString == "larari://inventory")
    }

    @Test func parsesWhatItBuilds() {
        let links: [LarariDeepLink] = [.shoppingStore(spaceID: space, scope: .store(store)),
                                        .shoppingStore(spaceID: space, scope: .stores([store, other])),
                                        .shoppingStore(spaceID: space, scope: .chain("spar")),
                                        .shoppingStore(spaceID: space, scope: .chain("tesco expressz")),
                                        .inventory(spaceID: space), .inventory(spaceID: nil)]
        for link in links {
            #expect(LarariDeepLink(url: link.url) == link)
        }
    }

    @Test func rejectsOtherLinks() {
        #expect(LarariDeepLink(url: URL(string: "https://larari.app/shopping")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://shopping?space=nope&store=nope")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://shopping?space=11111111-1111-1111-1111-111111111111")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://shopping?space=11111111-1111-1111-1111-111111111111&chain=")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://shopping?space=11111111-1111-1111-1111-111111111111&stores=nope")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://shopping?space=11111111-1111-1111-1111-111111111111&stores=22222222-2222-2222-2222-222222222222,x")!) == nil)
        #expect(LarariDeepLink(url: URL(string: "larari://settings")!) == nil)
        #expect(LarariDeepLink(url: URL(fileURLWithPath: "/tmp/Heti.larari")) == nil)   // archives go to the import router
    }
}
