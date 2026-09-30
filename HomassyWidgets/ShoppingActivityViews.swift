import AppIntents
import HomassyShared
import SwiftUI
import WidgetKit

/// Lock Screen banner (D1 A): store and household, "5 left", a thin progress bar, the next rows with tick buttons
/// and quantities (D8 A).
struct ShoppingLockScreenView: View {
    let state: ShoppingActivityContent
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ActivityTitle(state: state)
                Spacer(minLength: 8)
                if !state.isFinished {                                   // the "All done" row says it below
                    ActivityRemaining(state: state)
                }
            }
            if state.isFinished {
                Label("activity.done", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.mocha)
            } else {
                ActivityProgressBar(state: state)
                ActivityItemList(state: state, limit: ShoppingActivityContent.maxNextItems)
            }
            if isStale {
                Text("activity.stale")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

/// The store (or chain) and, below, the household with the list count from two lists up.
struct ActivityTitle: View {
    let state: ShoppingActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: state.title)
                .font(.headline)
                .lineLimit(1)
            Group {
                if state.listCount >= 2 {
                    Text("activity.subtitle.lists \(state.spaceName) \(state.listCount)")
                } else {
                    Text(verbatim: state.spaceName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ActivityRemaining: View {
    let state: ShoppingActivityContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("activity.remaining \(state.remainingCount)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .foregroundStyle(WidgetPalette.mocha)
            .fixedSize()                                                 // a long title truncates, not the count
    }
}

/// Compact trailing and minimal presentation (D2 A): the remaining count, a check when done.
struct ActivityCount: View {
    let state: ShoppingActivityContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state.isFinished {
                Image(systemName: "checkmark")
            } else {
                Text(verbatim: "\(state.remainingCount)")
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
        .foregroundStyle(WidgetPalette.mocha)
        .accessibilityLabel(state.isFinished ? Text("activity.done")
                                             : Text("activity.remaining \(state.remainingCount)"))
    }
}

struct ActivityProgressBar: View {
    let state: ShoppingActivityContent

    var body: some View {
        ProgressView(value: Double(state.doneCount), total: Double(max(state.totalCount, 1)))
            .tint(WidgetPalette.mocha)
            .accessibilityLabel(Text("activity.progress \(state.doneCount) \(state.totalCount)"))
    }
}

struct ActivityItemList: View {
    let state: ShoppingActivityContent
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.nextItems.prefix(limit)) { item in
                ActivityItemRow(item: item, canTick: state.canTick)
            }
            let more = state.remainingCount - min(limit, state.nextItems.count)
            if more > 0 {
                Text("activity.more \(more)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One row (D1 A, D8 A): a circle tick button (not in read-only households), the name, the quantity on the right.
/// The name truncates before the quantity. The button runs in the app process.
struct ActivityItemRow: View {
    let item: ShoppingActivityItem
    let canTick: Bool

    var body: some View {
        HStack(spacing: 10) {
            if canTick {
                Button(intent: TickShoppingItemIntent(itemIDs: item.itemIDs)) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(WidgetPalette.mocha)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("activity.tick.accessibility \(item.name)"))
            }
            HStack(spacing: 8) {
                Text(verbatim: item.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: item.quantity)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
