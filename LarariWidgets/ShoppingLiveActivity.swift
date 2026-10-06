import ActivityKit
import LarariShared
import SwiftUI
import WidgetKit

/// The shopping Live Activity (N-04): Lock Screen banner and Dynamic Island (D1 A, D2 A/A/A). The app starts,
/// updates and ends it; a tap opens the household's Shopping tab grouped by store.
struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            ShoppingLockScreenView(state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(WidgetPalette.mocha)
                .widgetURL(Self.link(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityTitle(state: context.state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isFinished {                       // the bottom row says "All done"
                        ActivityRemaining(state: context.state)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isFinished {
                        Label("activity.done", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(WidgetPalette.mocha)
                    } else {
                        ActivityItemList(state: context.state, limit: 2)
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(WidgetPalette.mocha)
                    .accessibilityLabel(Text("activity.accessibility.shopping"))
            } compactTrailing: {
                ActivityCount(state: context.state)
            } minimal: {
                ActivityCount(state: context.state)
            }
            .keylineTint(WidgetPalette.mocha)
            .widgetURL(Self.link(context.attributes))
        }
    }

    static func link(_ attributes: ShoppingActivityAttributes) -> URL {
        LarariDeepLink.shoppingStore(spaceID: attributes.spaceID, scope: attributes.scope).url
    }
}
