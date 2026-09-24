import SwiftUI

/// Motion tokens from the web app's main.css. Reduce Motion removes the movement and keeps the information.
enum Motion {
    /// `--bubble-in` 280 ms with `--bubble-ease-pop`: things appearing, with a slight overshoot.
    static let pop = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.28)
    /// `--bubble-move` 260 ms with `--bubble-ease-out`: things moving or settling into place.
    static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.26)
    /// `--bubble-out` 180 ms ease-in: things leaving.
    static let exit = Animation.easeIn(duration: 0.18)
    /// `--attribution-flash`: how long a row changed by someone else stays highlighted.
    static let attributionFlash: Duration = .milliseconds(1500)
    /// `--undo-window`: how long an optimistic change waits before it is saved.
    static let undoWindow: Duration = .seconds(5)
}

private struct MotionAwareAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that does nothing when Reduce Motion is on.
    func motionAware<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }
}

/// `withAnimation` that skips the animation when Reduce Motion is on. Read `reduceMotion` from
/// `@Environment(\.accessibilityReduceMotion)` in the calling view.
@MainActor
func withMotion<Result>(_ animation: Animation?, reduceMotion: Bool, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(reduceMotion ? nil : animation, body)
}

#if DEBUG
private struct MotionPreview: View {
    @State private var shown = false
    var body: some View {
        VStack(spacing: 24) {
            if shown {
                Circle().fill(Palette.accent).frame(width: 80, height: 80).transition(.scale.combined(with: .opacity))
            }
            Button { shown.toggle() } label: { Text(verbatim: "Toggle") }
        }
        .motionAware(Motion.pop, value: shown)
    }
}

#Preview { MotionPreview() }
#endif
