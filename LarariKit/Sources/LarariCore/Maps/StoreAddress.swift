import Foundation

/// A store's short address from Apple Maps (P2-08b), split for the compact label: the first comma part is the
/// street, the last one the locality ("Sport u. 2–4., Budaörs"). The Apple Maps category (P2-08c) rides along;
/// files written before it decode it as nil.
public struct StoreAddress: Codable, Equatable, Sendable {
    public let short: String
    public let street: String?
    public let locality: String?
    /// The `MKPointOfInterestCategory` raw value.
    public let category: String?

    public init?(short: String?, category: String? = nil) {
        guard let text = short?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        self.short = text
        self.category = category
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        street = parts.count >= 2 ? parts.first : nil
        locality = parts.count >= 2 ? parts.last : nil
    }
}
