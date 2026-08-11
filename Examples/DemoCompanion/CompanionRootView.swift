import FeatureFlag
import FeatureFlagUI
import SwiftUI

struct CompanionRootView: View {

    @StateObject private var loader = CompanionLoader()

    var body: some View {
        switch loader.state {
        case .loading:
            ProgressView().task { loader.load() }

        case let .ready(store):
            FlagBrowserView(store: store)

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

    private let appGroup = "group.com.andyyhope.featureflag.demo"

    func load() {
        do {
            state = .ready(try FlagEditingStore(appGroup: appGroup))
        } catch {
            state = .failed(
                """
                Launch the demo app at least once so it can publish its flags, and check \
                that both targets have the \(appGroup) App Group in their entitlements.
                """
            )
        }
    }
}
