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
                .safeAreaInset(edge: .bottom) { EventBar() }

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


/// Sends events to the host app.
///
/// Deliberately uses the acknowledged form: a Darwin notification has no delivery
/// receipt, so without waiting for the host to confirm, a button press into a closed app
/// would look exactly like a successful one.
struct EventBar: View {

    @State private var status: String?
    @State private var isSending = false

    private let channel = FlagEventChannel(appGroup: "group.com.andyyhope.featureflag.demo")

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(AppEvent.allCases, id: \.self) { event in
                    Button(event.eventDescription) { send(event) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
            .disabled(isSending || channel == nil)

            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func send(_ event: AppEvent) {
        guard let channel else { return }
        isSending = true
        status = nil

        Task {
            do {
                try await channel.send(event, timeout: 2)
                status = "\(event.eventDescription) — handled"
            } catch {
                status = "No response — is the Demo app open?"
            }
            isSending = false
        }
    }
}
