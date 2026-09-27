import Foundation
import Observation

/// One lot on the sheet (P2-08a): its own amount, storage location and expiry. Each lot becomes one stock item.
public struct StockLot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var quantityText: String
    /// `StorageLocation.publicId`; nil means no location.
    public var storageLocationID: UUID?
    /// Nil means no expiry date.
    public var expiresAt: Date?

    public init(id: UUID = UUID(), quantityText: String, storageLocationID: UUID? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.quantityText = quantityText
        self.storageLocationID = storageLocationID
        self.expiresAt = expiresAt
    }
}

/// The lot list shared by the add-stock sheet and the purchase sheet (P2-08a, layout 2A). It is never empty.
/// A new lot copies the last lot's location and expiry with an amount of 1.
@MainActor
@Observable
public final class StockLotsModel {
    public var lots: [StockLot]
    /// False when editing one stock item: no "Add lot", no delete.
    public let allowsMultiple: Bool
    public let storageOptions: [PickerOption]
    public private(set) var quantityErrors: [UUID: String] = [:]

    @ObservationIgnored private let locale: Locale

    public init(first: StockLot, storageOptions: [PickerOption], allowsMultiple: Bool, locale: Locale = .current) {
        lots = [first]
        self.storageOptions = storageOptions
        self.allowsMultiple = allowsMultiple
        self.locale = locale
    }

    public var canRemove: Bool { lots.count > 1 }
    public var lotCount: Int { lots.count }

    /// Every lot's amount; nil while any lot is not a number above 0.
    public var amounts: [Decimal]? {
        var values: [Decimal] = []
        for lot in lots {
            guard let value = parse(lot.quantityText) else { return nil }
            values.append(value)
        }
        return values
    }

    public var total: Decimal? { amounts?.reduce(0, +) }

    public func addLot() {
        guard allowsMultiple, let last = lots.last else { return }
        lots.append(StockLot(quantityText: Quantity.formatNumber(1, locale: locale),
                             storageLocationID: last.storageLocationID, expiresAt: last.expiresAt))
    }

    public func remove(_ id: UUID) {
        guard canRemove else { return }
        lots.removeAll { $0.id == id }
        quantityErrors[id] = nil
    }

    public func quantity(of id: UUID) -> Decimal? {
        lots.first { $0.id == id }.flatMap { parse($0.quantityText) }
    }

    /// The stepper: whole steps, never below 1. A fractional amount moves to the next whole number that way.
    public func step(_ id: UUID, by delta: Int) {
        guard let index = lots.firstIndex(where: { $0.id == id }) else { return }
        var value = parse(lots[index].quantityText) ?? 1
        var whole = Decimal()
        NSDecimalRound(&whole, &value, 0, delta > 0 ? .down : .up)
        lots[index].quantityText = Quantity.formatNumber(max(1, whole + Decimal(delta)), locale: locale)
        quantityErrors[id] = nil
    }

    /// Marks every lot whose amount is not a number above 0.
    public func validate() -> Bool {
        quantityErrors = [:]
        for lot in lots where parse(lot.quantityText) == nil {
            quantityErrors[lot.id] = coreLocalized("form.invalidQuantity")
        }
        return quantityErrors.isEmpty
    }

    /// The lots for the services, or nil (with `quantityErrors` set) when an amount is invalid.
    public func details() -> [LotDetails]? {
        guard validate(), let amounts else { return nil }
        return zip(lots, amounts).map { lot, amount in
            LotDetails(quantity: amount, storageLocationID: lot.storageLocationID, expiresAt: lot.expiresAt)
        }
    }

    /// The purchase sheet's inventory toggle carries the typed amount over to a single lot.
    public func setSingleQuantity(_ text: String) {
        guard lots.count == 1 else { return }
        lots[0].quantityText = text
    }

    public func storageName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return storageOptions.first { $0.id == id }?.name
    }

    private func parse(_ text: String) -> Decimal? {
        guard let value = Quantity.parse(text, locale: locale), value > 0 else { return nil }
        return value
    }
}
