import SwiftUI
import UIKit

/// Square product thumbnail; a Mocha-tinted icon tile when there is no image.
struct ProductImageView: View {
    let data: Data?
    var size: CGFloat? = 44

    var body: some View {
        ProductImageContent(data: data, iconScale: 0.45)
            .frame(width: size, height: size)
            .frame(maxWidth: size == nil ? .infinity : nil)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: size == nil ? 16 : 10, style: .continuous))
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
                GeometryReader { proxy in
                    Text(String(letter).uppercased())
                        .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.42, weight: .semibold,
                                      design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
