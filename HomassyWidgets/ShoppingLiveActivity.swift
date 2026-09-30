import ActivityKit
import HomassyShared
import SwiftUI
import WidgetKit

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            Text(verbatim: context.state.title)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text(verbatim: context.state.title) }
            } compactLeading: {
                Image(systemName: "cart.fill")
            } compactTrailing: {
                Text(verbatim: "\(context.state.remainingCount)")
            } minimal: {
                Text(verbatim: "\(context.state.remainingCount)")
            }
        }
    }
}
