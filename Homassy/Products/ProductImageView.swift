import SwiftUI
import UIKit

/// `.hero` is the product detail's header (P2-07a): a photo with radius 26, or a monogram circle like Contacts.
enum ProductImageStyle { case thumbnail, hero }

/// Square product thumbnail; a Mocha-tinted icon tile when there is no image.
struct ProductImageView: View {
    let data: Data?
    var size: CGFloat? = 44
    /// Without a photo, this name's first letter on a neutral tile (the product picker rows).
    var name: String?
    var style: ProductImageStyle = .thumbnail

    var body: some View {
        ProductImageContent(data: data, iconScale: 0.45, monogramOf: name)
            .frame(width: size, height: size)
            .frame(maxWidth: size == nil ? .infinity : nil)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(shape)
    }

    private var shape: AnyShape {
        switch style {
        case .thumbnail: AnyShape(RoundedRectangle(cornerRadius: size == nil ? 16 : 10, style: .continuous))
        case .hero: data == nil ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// The picture area at the top of a card: the product photo, or a monogram tile (the icon tile without a name).
struct ProductImageTile: View {
    let data: Data?
    /// Without a photo the tile shows this name's first letter on a neutral tile, like Contacts (user choice).
    var name: String?

    var body: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { ProductImageContent(data: data, iconScale: nil, monogramOf: name) }
            .clipped()
    }
}

private struct ProductImageContent: View {
    let data: Data?
    let iconScale: CGFloat?
    var monogramOf: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let letter = monogramOf?.trimmingCharacters(in: .whitespacesAndNewlines).first {
                // Drawn, not a Text: the letter is decoration sized to the tile, and a Text here would be audited as
                // fixed-size, low-contrast copy (X-04). The card's own label carries the name.
                Canvas { context, size in
                    let letterText = Text(String(letter).uppercased())
                        .font(.system(size: min(size.width, size.height) * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    context.draw(letterText, at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
                .background(Color(uiColor: .tertiarySystemFill))
            } else {
                GeometryReader { proxy in
                    Image(systemName: "shippingbox")
                        .font(.system(size: min(proxy.size.width, proxy.size.height) * (iconScale ?? 0.36)))
                        .foregroundStyle(Palette.mocha600)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Palette.mocha500.opacity(0.15))
            }
        }
        .accessibilityHidden(true)
        .task(id: data) { image = data.flatMap(UIImage.init(data:)) }
    }
}
