import Foundation

/// How the store picker reads a query (P2-08c): an address jumps the map there; anything else is a business
/// search, nearest first.
public enum StoreQuery {
    /// "Andrássy út 12", "Fő utca 1/A": at least one letter and one digit. A bare name or number is not.
    public static func isAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(where: \.isLetter) && trimmed.contains(where: \.isNumber)
    }
}
