import SwiftUI
import WidgetKit

/// Everything the widget extension shows: the shopping Live Activity (N-04); N-05 adds the widgets.
@main
struct HomassyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShoppingLiveActivity()
    }
}
