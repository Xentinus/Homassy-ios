import HomassyCore
import SwiftUI

/// A product card (README "Card layout"): picture, name, brand, barcode, eatable glyph, stock and expiry line.
/// Used by the Products grid (P2-07) and the Inventory grid (P2-08).
struct ProductCard: View {
    let card: ProductCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductImageTile(data: card.image)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if card.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                            .accessibilityLabel(Text("product.field.favorite"))
                    }
                }
                if let brand = card.brand {
                    Text(brand).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let barcode = card.barcode {
                    Label(barcode, systemImage: "barcode")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(Text("product.card.barcode \(barcode)"))
                }
                if card.isEatable || card.stockText != nil {
                    HStack(spacing: 6) {
                        if card.isEatable {
                            Image(systemName: "fork.knife")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("product.field.eatable"))
                        }
                        if let stock = card.stockText {
                            Text(stock).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
                if let expiry = card.expiryText {
                    Label(expiry, systemImage: card.expiryLevel.cardGlyph)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(card.expiryLevel.cardForeground)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(level: card.expiryLevel)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
