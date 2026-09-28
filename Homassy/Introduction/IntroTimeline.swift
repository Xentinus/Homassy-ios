import SwiftUI

/// Plays a scene's beats one by one while its page is the current one (P1-10a spec, "Motion rules").
/// `content` gets the beat, counting from 0 up to `delays.count`; the last value is the finished picture.
/// Reduce Motion shows the finished picture at once. Leaving the page rewinds it, so coming back replays it.
struct IntroTimeline<Content: View>: View {
    let isActive: Bool
    /// The wait before each beat.
    let delays: [Duration]
    @ViewBuilder let content: (Int) -> Content

    @State private var beat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(reduceMotion ? delays.count : beat)
            .task(id: isActive) {
                guard isActive else {
                    beat = 0
                    return
                }
                guard !reduceMotion else { return }
                beat = 0
                for delay in delays {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.settle) { beat += 1 }
                }
            }
    }
}

extension Array where Element == Duration {
    /// Durations from plain seconds, so a scene's beat list reads like the plan's beat map.
    static func seconds(_ values: Double...) -> [Duration] { values.map { .milliseconds(Int($0 * 1000)) } }
}
