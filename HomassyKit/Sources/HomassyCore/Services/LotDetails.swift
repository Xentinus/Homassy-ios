import Foundation

/// One lot of an addition (P2-08a): its amount, storage location and expiry. Each lot becomes one stock item.
public struct LotDetails: Sendable, Equatable {
    public var quantity: Decimal
    /// `StorageLocation.publicId`; nil means no location.
    public var storageLocationID: UUID?
    /// Nil means no expiry date.
    public var expiresAt: Date?

    public init(quantity: Decimal, storageLocationID: UUID? = nil, expiresAt: Date? = nil) {
        self.quantity = quantity
        self.storageLocationID = storageLocationID
        self.expiresAt = expiresAt
    }
}
