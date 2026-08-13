import FeatureFlag
import FeatureFlagUI
import SwiftUI

/// The whole companion.
///
/// Everything visible here is a choice rather than an implementation: which tabs, in
/// which order. Opening the shared store, the two ways that fails, the overrides and
/// flags screens, and sending signals all come from `FeatureFlagUI`.
///
/// An app with no signals and nothing of its own to add needs no view at all:
///
/// ```swift
/// FlagCompanionView(appGroup: "group.com.andyyhope.featureflag.demo")
/// ```
struct CompanionRootView: View {

    static let appGroup = "group.com.andyyhope.featureflag.demo"

    var body: some View {
        FlagCompanionView(
            appGroup: Self.appGroup,
            tabs: [
                // Overrides first: "what have I changed?" is the question you have before
                // filing a bug or handing the device to someone else.
                .overrides,
                .signals(AppSignal.self, appGroup: Self.appGroup),
                .flags,
                // The one tab only this app can supply — it is built around the demo's own
                // environment flag, and decides which payload the host fetches.
                .custom(id: "environment", title: "Environment", symbol: "square.stack.3d.up") {
                    EnvironmentTab(store: $0)
                },
            ]
        )
    }
}
