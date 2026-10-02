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

    /// The expiry line's text colour. Soon is secondary, like a Reminders due date (X-04 3B): yellow text is only
    /// 1.9:1 on white, so the yellow stays on the glyph and the corner badge.
    var cardForeground: Color {
        switch self {
        case .none, .ok, .soon, .critical: .secondary
        case .expired: Palette.expiryCritical
        }
    }

    /// The expiry line's glyph colour.
    var cardIconForeground: Color {
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

/// The expiry line of a card or row: the words in `cardForeground`, the glyph in `cardIconForeground`.
struct ExpiryLabel: View {
    let text: Text
    let level: ExpirationLevel

    init(_ text: Text, level: ExpirationLevel) {
        self.text = text
        self.level = level
    }

    init(_ string: String, level: ExpirationLevel) {
        self.init(Text(verbatim: string), level: level)
    }

    var body: some View {
        Label {
            text.foregroundStyle(level.cardForeground)
        } icon: {
            Image(systemName: level.cardGlyph).foregroundStyle(level.cardIconForeground)
        }
    }
}

extension View {
    /// The shared card chrome: neutral grouped background and rounded corners. The hairline shows only with
    /// Increase Contrast, as on iOS 26's own cards (P2-08d). A level draws the corner badge; the wide cards pass
    /// none and put the badge on their thumbnail instead.
    func cardChrome(level: ExpirationLevel = .none, cornerRadius: CGFloat = 16) -> some View {
        modifier(CardChrome(level: level, cornerRadius: cornerRadius))
    }
}

private struct CardChrome: ViewModifier {
    let level: ExpirationLevel
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay {
                if contrast == .increased { shape.strokeBorder(Color(uiColor: .separator), lineWidth: 1) }
            }
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
