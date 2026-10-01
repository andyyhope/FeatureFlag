import FeatureFlagUI
import SwiftUI
import WidgetKit

/// Shows a delayed signal's countdown in the Dynamic Island while you are in the host app.
@main
struct DemoCompanionWidgets: WidgetBundle {
    var body: some Widget {
        FlagSignalLiveActivity()
    }
}
