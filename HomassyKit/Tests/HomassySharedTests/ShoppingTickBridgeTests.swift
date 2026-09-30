import Foundation
import Testing
@testable import HomassyShared

@MainActor
@Suite("ShoppingTickBridge", .serialized)
struct ShoppingTickBridgeTests {
    @Test func withoutAHandlerNothingHappens() async {
        ShoppingTickBridge.unregister()
        #expect(!ShoppingTickBridge.isRegistered)
        #expect(await ShoppingTickBridge.tick([UUID()]) == false)
    }

    @Test func theRegisteredHandlerGetsTheItems() async {
        var received: [[UUID]] = []
        ShoppingTickBridge.register { received.append($0) }
        defer { ShoppingTickBridge.unregister() }
        let ids = [UUID(), UUID()]
        #expect(await ShoppingTickBridge.tick(ids))
        #expect(received == [ids])
    }
}
