import FeatureFlag
import FeatureFlagUI
import SwiftUI

struct CompanionRootView: View {

    @StateObject private var loader = CompanionLoader()
    @State private var selection: Tab = .overrides

    /// Ordered as the tab bar reads: what have I changed, what can I ask the app to do,
    /// what can I change, and which backend is it all pointed at.
    private enum Tab: Hashable {
        case overrides, signals, flags, environment
    }

    /// The selected tab shows a filled glyph, the rest an outline.
    ///
    /// Two things this depends on. Each symbol must actually ship a `.fill` variant —
    /// `slider.horizontal.3`, `server.rack` and `dot.radiowaves.left.and.right` do not,
    /// which is why none of them are here. And every label needs
    /// `.environment(\.symbolVariants, .none)`, because iOS fills tab bar glyphs for you
    /// and would otherwise render the outline name filled anyway. Setting that on the
    /// `TabView` is not enough; it has to be on the label inside `tabItem`.
    private func symbol(_ base: String, for tab: Tab) -> String {
        selection == tab ? base + ".fill" : base
    }

    var body: some View {
        switch loader.state {
        case .loading:
            ProgressView().task { loader.load() }

        case let .ready(store):
            // Three jobs, three tabs. Flags and signals are different in kind — one
            // changes what the app reads, the other asks it to act — and environment is
            // pulled out of the flag list because it is the switch you reach for first
            // and the one that moves everything else.
            TabView(selection: $selection) {
                // Overrides comes first: "what have I changed?" is the question you have
                // before filing a bug or handing the device to someone else, and it is
                // where the overrides leave the device.
                FlagOverridesView(store: store)
                    .tabItem {
                        Label("Overrides", systemImage: symbol("dial.medium", for: .overrides))
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(Tab.overrides)

                SignalsTab()
                    .tabItem {
                        Label("Signals", systemImage: symbol("paperplane", for: .signals))
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(Tab.signals)

                FlagBrowserView(store: store)
                    .tabItem {
                        Label("Flags", systemImage: symbol("flag", for: .flags))
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(Tab.flags)

                EnvironmentTab(store: store)
                    .tabItem {
                        Label(
                            "Environment",
                            systemImage: symbol("square.stack.3d.up", for: .environment)
                        )
                        .environment(\.symbolVariants, .none)
                    }
                    .tag(Tab.environment)
            }

        case let .failed(message):
            VStack(spacing: 12) {
                Text("No flags yet").font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { loader.load() }
            }
            .padding()
        }
    }
}

final class CompanionLoader: ObservableObject {

    enum State {
        case loading
        case ready(FlagEditingStore)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    static let appGroup = "group.com.andyyhope.featureflag.demo"

    func load() {
        do {
            state = .ready(try FlagEditingStore(appGroup: Self.appGroup))
        } catch {
            state = .failed(
                """
                Launch the demo app at least once so it can publish its flags, and check \
                that both targets have the \(Self.appGroup) App Group in their entitlements.
                """
            )
        }
    }
}
