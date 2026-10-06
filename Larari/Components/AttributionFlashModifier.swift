import LarariCore
import SwiftUI

/// Someone else changed this card (P5-04, the Apple-native option the user picked): a thin ring in their
/// member colour for 1.5 s. `AttributionCaption` puts "● Name · now" into the card's own text meanwhile,
/// the way Notes and Freeform show a collaborator's edits in the content instead of a floating label.
/// Reduce Motion: the ring and the caption appear and leave without animation. The colour is only the ring and
/// the dot, never a fill or text colour.
struct AttributionRing: ViewModifier {
    let ids: Set<UUID>
    var cornerRadius: CGFloat = 16

    @Environment(AttributionTracker.self) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.memberLookup) private var members

    func body(content: Content) -> some View {
        let attribution = tracker.attribution(forAnyOf: ids)
        content
            .overlay {
                if let attribution {
                    // Outside the card, like the web's box-shadow ring: the card's own border shows expiry.
                    RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                        .strokeBorder(accent(attribution), lineWidth: 2)
                        .padding(-3)
                        .transition(reduceMotion ? .identity : .opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: attribution != nil)
    }

    private func accent(_ attribution: Attribution) -> Color {
        Color.memberAccent(seed: attribution.userRecordName, key: members.colorKey(attribution.userRecordName))
    }
}

/// The card line that shows who changed it while the ring is on, otherwise `fallback`.
struct AttributionCaption<Fallback: View>: View {
    let ids: Set<UUID>
    @ViewBuilder let fallback: () -> Fallback

    @Environment(AttributionTracker.self) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.memberLookup) private var members

    var body: some View {
        Group {
            if let attribution = tracker.attribution(forAnyOf: ids) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.memberAccent(seed: attribution.userRecordName,
                                                 key: members.colorKey(attribution.userRecordName)))
                        .frame(width: 6, height: 6)
                    Text("attribution.byNow \(members.name(attribution.userRecordName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Part of the card's combined label, so VoiceOver reads who changed it.
                .transition(reduceMotion ? .identity : .opacity)
            } else {
                fallback()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: tracker.attribution(forAnyOf: ids) != nil)
    }
}

extension View {
    func attributionRing(_ ids: Set<UUID>, cornerRadius: CGFloat = 16) -> some View {
        modifier(AttributionRing(ids: ids, cornerRadius: cornerRadius))
    }
}
