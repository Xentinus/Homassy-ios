import Foundation

/// `Array.move(fromOffsets:toOffset:)` lives in SwiftUI; HomassyCore needs the same semantics without it.
public enum Reordering {
    public static func move<T>(_ elements: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let valid = source.filter { $0 >= 0 && $0 < elements.count }
        let moving = valid.sorted().map { elements[$0] }
        var remaining = elements.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let shift = valid.filter { $0 < destination }.count
        let insertAt = min(max(destination - shift, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        return remaining
    }
}
