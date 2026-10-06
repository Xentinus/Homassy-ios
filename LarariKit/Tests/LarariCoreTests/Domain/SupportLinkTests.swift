import Foundation
import Testing
@testable import LarariCore

@Suite("SupportLink")
struct SupportLinkTests {
    @Test func isOurHTTPSSupportPage() throws {
        let components = try #require(URLComponents(url: SupportLink.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "larari.app")
        #expect(components.path == "/support")
        #expect(components.query == nil)
        #expect(components.fragment == nil)
        #expect(components.port == nil)
    }
}
