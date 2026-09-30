import Foundation
import Testing
@testable import HomassyShared

@Suite("ShoppingActivityContent")
struct ShoppingActivityContentTests {
    func item(_ name: String, quantity: String = "1 db", ids: Int = 1) -> ShoppingActivityItem {
        ShoppingActivityItem(id: "i:\(name)", itemIDs: (0..<ids).map { _ in UUID() }, name: name, quantity: quantity)
    }

    func content(remaining: Int, done: Int, names: [String] = ["Tej"]) -> ShoppingActivityContent {
        ShoppingActivityContent(title: "Spar Budaörs", spaceName: "Otthon", listCount: 2, remainingCount: remaining,
                                doneCount: done, nextItems: names.map { item($0) }, canTick: true)
    }

    @Test func countsAndFinishedState() {
        #expect(content(remaining: 5, done: 3).totalCount == 8)
        #expect(!content(remaining: 5, done: 3).isFinished)
        #expect(content(remaining: 0, done: 8, names: []).isFinished)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = content(remaining: 2, done: 1, names: ["Tej", "Kenyér"])
        let decoded = try JSONDecoder().decode(ShoppingActivityContent.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func scopesRoundTripThroughJSON() throws {
        for scope in [ShoppingActivityScope.store(UUID()), .stores([UUID(), UUID()]), .chain("tesco expressz")] {
            let decoded = try JSONDecoder().decode(ShoppingActivityScope.self, from: JSONEncoder().encode(scope))
            #expect(decoded == scope)
        }
    }

    @Test func onlyAChainScopeIsAChain() {
        #expect(ShoppingActivityScope.chain("spar").isChain)
        #expect(!ShoppingActivityScope.store(UUID()).isChain)
        #expect(!ShoppingActivityScope.stores([UUID(), UUID()]).isChain)
    }

    @Test func staysWellUnderActivityKitsFourKilobytes() throws {
        let long = String(repeating: "é", count: 40)
        let full = ShoppingActivityContent(
            title: long, spaceName: long, listCount: 99, remainingCount: 999, doneCount: 999,
            nextItems: (0..<ShoppingActivityContent.maxNextItems).map { _ in item(long, quantity: "12,5 befőttesüveg", ids: 4) },
            canTick: true)
        #expect(try JSONEncoder().encode(full).count < 2_048)
    }
}
