import Foundation

public enum ServiceError: Error, Equatable, LocalizedError {
    case nameRequired, quantityMustBePositive, expiryBeforePurchase, readOnlySpace, notFound

    var catalogKey: String {
        switch self {
        case .nameRequired: "error.nameRequired"
        case .quantityMustBePositive: "error.quantityMustBePositive"
        case .expiryBeforePurchase: "error.expiryBeforePurchase"
        case .readOnlySpace: "error.readOnlySpace"
        case .notFound: "error.notFound"
        }
    }

    public var errorDescription: String? {
        Bundle.module.localizedString(forKey: catalogKey, value: nil, table: "Localizable")
    }
}
