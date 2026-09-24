import Foundation
import Testing
@testable import HomassyCore

@Suite("Reordering")
struct ReorderingTests {
    static let abcd = ["a", "b", "c", "d"]

    @Test("Matches SwiftUI onMove semantics", arguments: [
        ([0], 2, ["b", "a", "c", "d"]),
        ([3], 0, ["d", "a", "b", "c"]),
        ([1, 2], 4, ["a", "d", "b", "c"]),
        ([0], 4, ["b", "c", "d", "a"]),
        ([2], 2, ["a", "b", "c", "d"]),
        ([0, 3], 2, ["b", "a", "d", "c"]),
    ])
    func move(source: [Int], destination: Int, expected: [String]) {
        #expect(Reordering.move(Self.abcd, fromOffsets: IndexSet(source), toOffset: destination) == expected)
    }
}
