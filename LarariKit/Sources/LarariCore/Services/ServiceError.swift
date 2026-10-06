import Foundation

public enum ServiceError: Error, Equatable, LocalizedError {
    case nameRequired, quantityMustBePositive, expiryBeforePurchase, readOnlySpace, notFound
    /// Consume or move asked for more than the stock item holds (P2-06; never clamped).
    case quantityExceedsStock
    /// A product link that is not an http(s) address (user request, 2026-09-24).
    case invalidURL

    var catalogKey: String {
        switch self {
        case .nameRequired: "error.nameRequired"
        case .quantityMustBePositive: "error.quantityMustBePositive"
        case .expiryBeforePurchase: "error.expiryBeforePurchase"
        case .readOnlySpace: "error.readOnlySpace"
        case .notFound: "error.notFound"
        case .quantityExceedsStock: "error.quantityExceedsStock"
        case .invalidURL: "error.invalidURL"
        }
    }

    public var errorDescription: String? {
        Bundle.module.localizedString(forKey: catalogKey, value: nil, table: "Localizable")
    }
}
