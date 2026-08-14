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
                // Two enums, two groups. The host observes each separately, so its
                // configuration handler never has to mention caches.
                .signals(
                    [
                        .group("Configuration", AppSignal.self),
                        .group("Caches", CacheSignal.self),
                    ],
                    appGroup: Self.appGroup
                ),
                .flags,
                // The environment flag earns a screen because changing it makes the host
                // fetch a different payload, so half the values on the Flags tab move
                // with it. Which key that is, is knowledge about this app.
                .detail(key: "environment", title: "Environment"),
            ]
        )
    }
}
