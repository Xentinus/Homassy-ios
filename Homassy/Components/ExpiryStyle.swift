import HomassyCore
import SwiftUI

/// Card styling for an expiry level (README "Card layout", user rule): neutral beyond 14 days or without a date,
/// yellow within 14 days (soon and critical alike), red once expired.
extension ExpirationLevel {
    var cardGlyph: String {
        switch self {
        case .none, .ok: "calendar"
        case .soon, .critical: "clock"
        case .expired: "alarm"
        }
    }

    /// The expiry line's colour.
    var cardForeground: Color {
        switch self {
        case .none, .ok: .secondary
        case .soon, .critical: Palette.expirySoon
        case .expired: Palette.expiryCritical
        }
    }

    /// The card border; nil for the neutral hairline.
    var cardBorder: Color? {
        switch self {
        case .none, .ok: nil
        case .soon, .critical: Palette.expirySoon
        case .expired: Palette.expiryCritical
        }
    }

    /// A faint wash over the card background; clear when neutral.
    var cardWash: Color {
        cardBorder?.opacity(0.08) ?? .clear
    }
}

extension View {
    /// The shared card chrome: grouped background, rounded corners, expiry wash and border.
    func cardChrome(level: ExpirationLevel = .none, cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(level.cardWash, in: shape)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay {
                if let border = level.cardBorder {
                    shape.strokeBorder(border, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
                }
            }
            .clipShape(shape)
    }
}
