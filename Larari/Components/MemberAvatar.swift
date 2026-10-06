import SwiftUI
import UIKit

/// A neutral avatar (photo or initials) with the member colour as a ring only.
struct MemberAvatar: View {
    let name: String
    let colorSeed: String?
    var colorKey: String?
    let avatar: Data?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            if let avatar, let image = UIImage(data: avatar) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(ring, lineWidth: size > 60 ? 3 : 2)
        }
        .accessibilityHidden(true)
    }

    private var ring: Color {
        guard let colorSeed else { return Color(.separator) }
        return Color.memberAccent(seed: colorSeed, key: colorKey)
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
