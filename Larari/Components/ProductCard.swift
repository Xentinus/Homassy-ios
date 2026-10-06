import LarariCore
import SwiftUI

/// A product card (P2-08d, user pick 2A): thumbnail, name and brand, then the stock and the nearest expiry on the
/// trailing side. Used by the Inventory tab and the Search catalogue. A tap opens the product detail.
struct ProductCard: View {
    let card: ProductCardData
    /// Search shows "Nincs készleten" for a product without stock; Inventory never has an empty card.
    var showsOutOfStock = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        WideCardLayout(image: card.image, name: card.name, level: card.expiryLevel) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                if card.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel(Text("product.field.favorite"))
                }
            }
            AttributionCaption(ids: card.relatedIDs) {
                if let secondary = secondaryLine {
                    Text(secondary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } trailing: {
            if let stock = card.stockText {
                Text(stock).font(.headline).monospacedDigit()
                if let expiry = card.expiryText {
                    ExpiryLabel(expiry, level: card.expiryLevel).font(.caption.weight(.medium))
                }
            } else if showsOutOfStock {
                Text("product.detail.noItems").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .attributionRing(card.relatedIDs)
        .accessibilityElement(children: .combine)
    }

    /// The brand, or in the Inventory name and expiry groupings "places · brand" (P2-08e, user pick 6C). The places
    /// come first, so a long line truncates the brand.
    private var secondaryLine: String? {
        let parts = [card.placesText, card.brand].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
