import Foundation

/// A store's short address from Apple Maps (P2-08b), split for the compact label: the first comma part is the
/// street, the last one the locality ("Sport u. 2–4., Budaörs").
public struct StoreAddress: Codable, Equatable, Sendable {
    public let short: String
    public let street: String?
    public let locality: String?

    public init?(short: String?) {
        guard let text = short?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        self.short = text
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        street = parts.count >= 2 ? parts.first : nil
        locality = parts.count >= 2 ? parts.last : nil
    }
}
