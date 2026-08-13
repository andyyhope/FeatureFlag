import FeatureFlag
import FeatureFlagUI
import SwiftUI

/// The whole companion, minus the two tabs that are particular to this app.
///
/// Opening the shared store, reporting the two ways that fails, and the Overrides and
/// Flags tabs all come from `FlagCompanionView` — none of it is specific to the demo, so
/// none of it lives here. What is left is what only this app can supply: an Environment
/// tab built around its own `environment` flag, and a Signals tab that sends its own
/// `AppSignal` cases.
///
/// A companion with nothing app-specific to add needs no view at all:
///
/// ```swift
/// FlagCompanionView(appGroup: "group.com.andyyhope.featureflag.demo")
/// ```
struct CompanionRootView: View {

    /// Ordered as the tab bar reads: what have I changed, what can I ask the app to do,
    /// what can I change, and which backend is it all pointed at.
    private enum Tab: Hashable {
        case overrides, signals, flags, environment
    }

    static let appGroup = "group.com.andyyhope.featureflag.demo"

    @State private var selection: Tab = .overrides

    var body: some View {
        FlagCompanionView(appGroup: Self.appGroup) { store in
            TabView(selection: $selection) {
                // Overrides comes first: "what have I changed?" is the question you have
                // before filing a bug or handing the device to someone else, and it is
                // where the overrides leave the device.
                FlagOverridesView(store: store)
                    .flagCompanionTab(
                        "Overrides", symbol: "dial.medium", isSelected: selection == .overrides
                    )
                    .tag(Tab.overrides)

                SignalsTab()
                    .flagCompanionTab(
                        "Signals", symbol: "paperplane", isSelected: selection == .signals
                    )
                    .tag(Tab.signals)

                FlagBrowserView(store: store)
                    .flagCompanionTab(
                        "Flags", symbol: "flag", isSelected: selection == .flags
                    )
                    .tag(Tab.flags)

                EnvironmentTab(store: store)
                    .flagCompanionTab(
                        "Environment", symbol: "square.stack.3d.up",
                        isSelected: selection == .environment
                    )
                    .tag(Tab.environment)
            }
        }
    }
}
