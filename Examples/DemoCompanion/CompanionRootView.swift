import FeatureFlag
import FeatureFlagUI
import SwiftUI

struct CompanionRootView: View {

    @StateObject private var loader = CompanionLoader()
    @State private var selection = 0

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
                    .tabItem { Label("Overrides", systemImage: "slider.horizontal.3") }
                    .tag(0)

                FlagBrowserView(store: store)
                    .tabItem { Label("Flags", systemImage: "flag") }
                    .tag(1)

                EnvironmentTab(store: store)
                    .tabItem { Label("Environment", systemImage: "server.rack") }
                    .tag(2)

                SignalsTab()
                    .tabItem { Label("Signals", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(3)
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
