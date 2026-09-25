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

    /// The corner badge's colour and symbol (Apple-native direction, user choice 2026-09-25); nil when neutral.
    /// The card itself is never tinted: the badge and the expiry line carry the state, with a glyph and text,
    /// so colour is never the only signal.
    var cardBadge: (color: Color, symbol: String)? {
        switch self {
        case .none, .ok: nil
        case .soon, .critical: (Palette.expirySoon, "clock")
        case .expired: (Palette.expiryCritical, "exclamationmark")
        }
    }
}

extension View {
    /// The shared card chrome: neutral grouped background, hairline and rounded corners, plus the expiry
    /// badge in the top-right corner for soon (yellow) and expired (red) cards.
    func cardChrome(level: ExpirationLevel = .none, cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay { shape.strokeBorder(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5) }
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                if let badge = level.cardBadge {
                    Image(systemName: badge.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(badge.color, in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .padding(8)
                        .accessibilityHidden(true)      // the expiry line says it in words
                }
            }
    }
}
