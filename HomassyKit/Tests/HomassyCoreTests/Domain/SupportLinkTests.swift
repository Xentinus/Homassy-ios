import Foundation
import Testing
@testable import HomassyCore

@Suite("SupportLink")
struct SupportLinkTests {
    @Test func isOurHTTPSSupportPage() throws {
        let components = try #require(URLComponents(url: SupportLink.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "homassy.com")
        #expect(components.path == "/support")
        #expect(components.query == nil)
        #expect(components.fragment == nil)
        #expect(components.port == nil)
    }
}
