import Foundation

/// A store's chain, derived from its name (P4-06): lowercased, without diacritics, the first word, except known
/// multi-word brands. "Auchan Budaörs" and "AUCHAN Csömör" are both `auchan`, so a reminder fires at any Auchan.
public enum ChainKey {
    public static let multiWordBrands: Set<String> = ["tesco expressz", "tesco extra", "cba prima", "spar partner", "coop szuper"]

    public static func make(_ storeName: String) -> String {
        let words = foldedWords(storeName)
        guard let first = words.first else { return "" }
        if words.count >= 2, multiWordBrands.contains("\(first) \(words[1])") { return "\(first) \(words[1])" }
        return first
    }

    /// The key's words as most of the stores spell them ("Auchan" for "Auchan Budaörs", "AUCHAN").
    public static func displayName(of storeNames: [String]) -> String {
        let spellings = storeNames.compactMap { name -> String? in
            let wordCount = make(name).split(separator: " ").count
            let original = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(wordCount)
            return original.isEmpty ? nil : original.joined(separator: " ")
        }
        let counts = Dictionary(grouping: spellings, by: { $0 }).mapValues(\.count)
        return spellings.max { lhs, rhs in
            counts[lhs, default: 0] != counts[rhs, default: 0]
                ? counts[lhs, default: 0] < counts[rhs, default: 0]
                : spellings.firstIndex(of: lhs)! > spellings.firstIndex(of: rhs)!
        } ?? ""
    }

    private static func foldedWords(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
