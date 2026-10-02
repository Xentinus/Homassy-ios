import HomassyCore
import SwiftUI

/// The wide card (P2-08d, user pick 2A, the Fitness Workouts / Find My Items pattern): a thumbnail with the expiry
/// badge on its corner, the name and one secondary line in the middle, the amount and its date on the trailing side.
/// Lines without data are simply not passed in, so the card is only as tall as its content (user rule: no reserved
/// empty lines). At accessibility sizes the trailing column moves under the name and nothing truncates.
struct WideCardLayout<Middle: View, Trailing: View>: View {
    let image: Data?
    /// The monogram letter's source when there is no photo.
    let name: String
    var level: ExpirationLevel = .none
    var thumbnailSize: CGFloat = 44
    var cornerRadius: CGFloat = 16
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 17

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(alignment: stacked ? .top : .center, spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) { middle() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 2) { trailing() }
                .fixedSize(horizontal: !stacked, vertical: false)
        }
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(cornerRadius: cornerRadius)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var thumbnail: some View {
        // Capped: at accessibility sizes the scaled badge grew to the size of the 44 pt thumbnail and hid the monogram.
        let badgeSize = min(self.badgeSize, 22)
        return ProductImageView(data: image, size: thumbnailSize, name: name)
            .overlay(alignment: .topTrailing) {
                if let badge = level.cardBadge {
                    Image(systemName: badge.symbol)
                        .font(.system(size: badgeSize * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(badge.color, in: Circle())
                        .overlay { Circle().strokeBorder(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 1.5) }
                        .offset(x: 5, y: -5)
                        .accessibilityHidden(true)      // the expiry line says it in words
                }
            }
            .accessibilityHidden(true)
    }
}
