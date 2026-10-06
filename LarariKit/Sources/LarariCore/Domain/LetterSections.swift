import Foundation

/// The alphabetical section rule shared by the Search catalogue, Inventory and Shopping (P2-08e): the first character
/// folded (diacritics and case ignored, uppercased), so "Áfonya" is under A and "öntet" under O. A name that does not
/// start with a letter goes under "#", which sorts last.
public enum LetterSections {
    public static let other = "#"

    public static func key(for name: String, locale: Locale) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return other }
        let folded = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .uppercased(with: locale)
        return folded.first?.isLetter == true ? folded : other
    }

    /// A–Z by the standard comparison, "#" last.
    public static func sortedKeys<S: Sequence>(_ keys: S) -> [String] where S.Element == String {
        keys.sorted { lhs, rhs in
            if lhs == other || rhs == other { return rhs == other && lhs != other }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// The values in letter sections, each section sorted by name.
    public static func group<T>(_ values: [T], locale: Locale, name: (T) -> String) -> [(key: String, values: [T])] {
        let grouped = Dictionary(grouping: values) { key(for: name($0), locale: locale) }
        return sortedKeys(grouped.keys).map { key in
            (key, (grouped[key] ?? []).sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending })
        }
    }
}
