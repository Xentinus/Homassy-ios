import Foundation

/// One priced purchase of a product (P4-05): a `PurchaseRecord` with a price, or an older stock item with a
/// price and no record. `price` is the amount paid for `quantity`.
public struct PriceEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let storeID: UUID?
    public let storeName: String?
    public let quantity: Decimal
    public let unit: MeasureUnit
    public let price: Decimal
    public let currency: String

    public init(id: UUID, date: Date, storeID: UUID?, storeName: String?, quantity: Decimal, unit: MeasureUnit,
                price: Decimal, currency: String) {
        self.id = id
        self.date = date
        self.storeID = storeID
        self.storeName = storeName
        self.quantity = quantity
        self.unit = unit
        self.price = price
        self.currency = currency
    }

    /// Price for one unit; the amount paid when the quantity is unknown.
    public var unitPrice: Decimal { quantity > 0 ? price / quantity : price }

    /// The key of the store line this entry belongs to ("none" without a store).
    public var storeKey: String { storeID?.uuidString ?? PriceHistory.noStoreKey }
}

/// Average and per-store view of a product's purchases (user request, 2026-09-25).
public struct PriceSummary: Equatable, Sendable {
    public struct Average: Equatable, Sendable {
        public let unitPrice: Decimal
        public let currency: String
        public let unit: MeasureUnit
        public let count: Int
    }

    public struct StoreLine: Identifiable, Equatable, Sendable {
        public var id: String { key }
        public let key: String
        public let storeID: UUID?
        public let name: String?
        public let latest: PriceEntry
        public let count: Int
    }

    public let average: Average?
    /// Newest purchase first.
    public let stores: [StoreLine]

    public var isEmpty: Bool { stores.isEmpty }
}

public enum PriceHistory {
    public static let noStoreKey = "none"

    @MainActor
    public static func entries(for product: Product, defaultCurrency: String) -> [PriceEntry] {
        let recorded = product.purchaseRecordSet.compactMap { record -> PriceEntry? in
            guard let price = record.price else { return nil }
            return PriceEntry(id: record.publicId, date: record.purchasedAt ?? record.createdAt,
                              storeID: record.shoppingLocation?.publicId, storeName: record.shoppingLocation?.name,
                              quantity: record.quantity, unit: record.unit, price: price,
                              currency: record.currency ?? defaultCurrency)
        }
        // Stock priced before purchase records existed still counts.
        let legacy = product.inventoryItemSet.compactMap { item -> PriceEntry? in
            guard let price = item.price, item.purchaseRecordSet.isEmpty else { return nil }
            return PriceEntry(id: item.publicId, date: item.purchasedAt ?? item.createdAt,
                              storeID: item.shoppingLocation?.publicId, storeName: item.shoppingLocation?.name,
                              quantity: item.purchasedQuantity, unit: item.unit, price: price,
                              currency: item.currency ?? defaultCurrency)
        }
        return (recorded + legacy).sorted { $0.date > $1.date }
    }

    /// The average unit price over the most common currency and unit, and each store's latest purchase.
    public static func summary(of entries: [PriceEntry], preferredCurrency: String? = nil) -> PriceSummary {
        PriceSummary(average: average(of: entries, preferredCurrency: preferredCurrency), stores: stores(of: entries))
    }

    /// One store's purchases for the chart, oldest first.
    public static func chart(_ entries: [PriceEntry], storeKey: String) -> [PriceEntry] {
        entries.filter { $0.storeKey == storeKey }.sorted { $0.date < $1.date }
    }

    private static func average(of entries: [PriceEntry], preferredCurrency: String?) -> PriceSummary.Average? {
        guard let currency = mostCommon(entries.map(\.currency), preferring: preferredCurrency) else { return nil }
        let inCurrency = entries.filter { $0.currency == currency }
        guard let unitRaw = mostCommon(inCurrency.map(\.unit.rawValue), preferring: nil),
              let unit = MeasureUnit(rawValue: unitRaw) else { return nil }
        let matching = inCurrency.filter { $0.unit == unit }
        guard !matching.isEmpty else { return nil }
        let total = matching.reduce(Decimal(0)) { $0 + $1.unitPrice }
        return PriceSummary.Average(unitPrice: total / Decimal(matching.count), currency: currency, unit: unit,
                                    count: matching.count)
    }

    private static func stores(of entries: [PriceEntry]) -> [PriceSummary.StoreLine] {
        Dictionary(grouping: entries, by: \.storeKey)
            .compactMap { key, group -> PriceSummary.StoreLine? in
                guard let latest = group.max(by: { $0.date < $1.date }) else { return nil }
                return PriceSummary.StoreLine(key: key, storeID: latest.storeID, name: latest.storeName,
                                              latest: latest, count: group.count)
            }
            .sorted { $0.latest.date > $1.latest.date }
    }

    /// The most frequent value; ties go to `preferring`, then alphabetical.
    private static func mostCommon(_ values: [String], preferring: String?) -> String? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            if a.key == preferring { return false }
            if b.key == preferring { return true }
            return a.key > b.key
        }?.key
    }
}
