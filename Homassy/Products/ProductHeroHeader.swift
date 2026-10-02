import HomassyCore
import SwiftUI
import UIKit

/// The product detail's header (P2-07a, 4A + 5A, the Contacts pattern): a large photo or monogram circle, the name,
/// "brand · category", the barcode line, and the Kedvenc / Listára / Weboldal action row.
struct ProductHeroHeader: View {
    let fields: ProductFields
    let canEdit: Bool
    let canAddToList: Bool
    let toggleFavorite: () -> Void
    let addToList: () -> Void
    /// Whether the name is on screen; the navigation bar shows the title only once it has scrolled away.
    let nameVisible: (Bool) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 4) {
            ProductImageView(data: fields.image, size: 112, name: fields.name, style: .hero)
                .padding(.bottom, 8)
            Text(verbatim: fields.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("product.detail.name")
                .onScrollVisibilityChange(threshold: 0.1, nameVisible)
            if let subtitle {
                Text(verbatim: subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let barcode = fields.barcode, !barcode.isEmpty {
                // At accessibility sizes the glyph sits above the digits, so the number keeps the full width and
                // shrinks on one line instead of breaking mid-number.
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    Image(systemName: "barcode")
                    Text(verbatim: barcode).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button { UIPasteboard.general.string = barcode } label: {
                            Label("product.detail.copy", systemImage: "doc.on.doc")
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("product.field.barcode"))
                    .accessibilityValue(Text(verbatim: barcode).speechSpellsOutCharacters())
                    .accessibilityIdentifier("product.detail.barcode")
            }
            actionRow.padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String? {
        let parts = [fields.brand, fields.category].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: toggleFavorite) {
                HeroActionLabel(title: "product.field.favorite", systemImage: fields.isFavorite ? "heart.fill" : "heart")
            }
            .disabled(!canEdit)
            .accessibilityValue(Text(fields.isFavorite ? "common.yes" : "common.no"))
            .accessibilityIdentifier("product.detail.favorite")
            Button(action: addToList) {
                HeroActionLabel(title: "product.detail.addToList", systemImage: "cart.badge.plus")
            }
            .disabled(!canEdit || !canAddToList)
            .accessibilityHint(canAddToList ? Text(verbatim: "") : Text("product.detail.addToList.noList"))
            .accessibilityIdentifier("product.detail.addToList")
            if let url = fields.url {
                Button { openURL(url) } label: {
                    HeroActionLabel(title: "product.detail.website", systemImage: "link")
                }
                .accessibilityValue(Text(verbatim: url.host() ?? url.absoluteString))
                .accessibilityIdentifier("product.detail.link")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(HeroActionButtonStyle())
    }
}

private struct HeroActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3).accessibilityHidden(true)
            Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
    }
}

/// A tinted tile like the Contacts action buttons. A custom style also keeps each button's tap its own inside the
/// list row.
private struct HeroActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .foregroundStyle(isEnabled ? Palette.accent : Color.secondary)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
