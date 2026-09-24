import HomassyCore
import SwiftUI

/// Shows the newest pending change with an Undo button, or the commit failure message.
/// Attach with `.overlay(alignment: .bottom)` inside a tab (or a full-screen cover) so it clears the tab bar.
struct UndoToastOverlay: View {
    @Environment(UndoQueue.self) private var queue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let title = queue.toastTitle {
                UndoToast(title: title, kind: queue.dominantKind, windowStartedAt: queue.windowStartedAt,
                          window: queue.undoWindow) {
                    withMotion(Motion.settle, reduceMotion: reduceMotion) { queue.undoAll() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if queue.lastError != nil {
                UndoFailureToast { queue.clearError() }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .motionAware(Motion.settle, value: queue.pending.map(\.id))
        .motionAware(Motion.settle, value: queue.lastError != nil)
        .onChange(of: queue.toastTitle) { _, title in
            if let title { AccessibilityNotification.Announcement(title).post() }
        }
        .onChange(of: queue.lastError != nil) { _, failed in
            if failed { AccessibilityNotification.Announcement(String(localized: "undo.failed")).post() }
        }
    }
}

/// The undo card (user decision, 2026-09-24): a neutral card with a Mocha action icon, the title, a filled Mocha
/// Undo button, and a draining Mocha bar for the shared window. Under Reduce Motion the bar is replaced by a seconds count, so the deadline stays legible.
private struct UndoToast: View {
    let title: String
    let kind: UndoKind?
    let windowStartedAt: Date?
    let window: Duration
    let undo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.mocha600)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if reduceMotion { secondsLeft }
                Button("undo.action", action: undo)
                    .font(.subheadline.bold())
                    .foregroundStyle(Palette.mochaButtonForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.mochaButtonBackground, in: .capsule)
                    .accessibilityIdentifier("undoToast.undo")
            }
            if !reduceMotion { drainingBar }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, reduceMotion ? 12 : 10)
        .frame(maxWidth: 560)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
    }

    private var symbol: String {
        switch kind {
        case .delete: "trash"
        case .consume: "fork.knife"
        case .move: "arrow.left.arrow.right"
        case .purchase: "cart"
        case .generic, nil: "arrow.uturn.backward"
        }
    }

    private var drainingBar: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                Capsule()
                    .fill(Palette.mocha100)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Palette.mocha500)
                            .frame(width: proxy.size.width * remaining(at: context.date))
                    }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var secondsLeft: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int((remaining(at: context.date) * window.seconds).rounded(.up))
            Text(verbatim: "\(seconds)")
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    /// 1 at the start of the window, 0 at its end.
    private func remaining(at date: Date) -> Double {
        guard let windowStartedAt else { return 1 }
        let elapsed = date.timeIntervalSince(windowStartedAt)
        return min(1, max(0, 1 - elapsed / window.seconds))
    }
}

private struct UndoFailureToast: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("undo.failed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.expiryCritical)
            Spacer(minLength: 8)
            Button("common.close", action: dismiss)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.expiryCritical.opacity(0.7), lineWidth: 1.5) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast.failure")
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

#Preview("Toast") {
    let queue = UndoQueue()
    queue.enqueue(UndoableAction(title: UndoTitle.removed("Milk"), revert: {}, commit: {}))
    return Color.clear
        .overlay(alignment: .bottom) { UndoToastOverlay() }
        .environment(queue)
}

#Preview("Toast, landscape", traits: .landscapeLeft) {
    let queue = UndoQueue()
    queue.enqueue(UndoableAction(title: UndoTitle.removed("Milk"), revert: {}, commit: {}))
    queue.enqueue(UndoableAction(title: UndoTitle.removed("Bread"), revert: {}, commit: {}))
    return Color.clear
        .overlay(alignment: .bottom) { UndoToastOverlay() }
        .environment(queue)
}
