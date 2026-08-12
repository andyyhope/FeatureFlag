import FeatureFlag
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var model: DemoModel

    private var flags: FlagPole<AppFlags> { model.flags }

    var body: some View {
        NavigationStack {
            List {
                liveValues
                remoteConfiguration
                provenance
                combine
            }
            .navigationTitle("Demo")
        }
    }

    // MARK: - What the app sees

    private var liveValues: some View {
        Section("Live flag values") {
            LabeledContent("New onboarding", value: "\(flags.newOnboarding)")
            LabeledContent("Page size", value: "\(flags.pageSize)")
            LabeledContent("Markets", value: flags.markets.joined(separator: ", "))
            LabeledContent("Apple Pay", value: "\(flags.checkout.applePay)")
            LabeledContent("Tier", value: flags.checkout.tier.rawValue)
            LabeledContent("Endpoint", value: flags.checkout.endpoint.host() ?? "—")
            LabeledContent("One tap", value: "\(flags.checkout.express.oneTap)")
        }
    }

    // MARK: - Remote payloads

    private var remoteConfiguration: some View {
        Section {
            ForEach(RemoteConfiguration.all) { configuration in
                Button {
                    model.apply(configuration)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(configuration.name)
                            Text(configuration.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if model.appliedConfiguration == configuration {
                            Image(systemName: "checkmark")
                        } else if configuration.isDeliberatelyBroken {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if model.appliedConfiguration != nil {
                Button("Clear remote payload", role: .destructive) { model.clearRemote() }
            }

            if let rejection = model.rejection {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rejected, nothing applied")
                        .font(.footnote.weight(.semibold))
                    Text(rejection)
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.red)
            }
        } header: {
            Text("Remote configuration")
        } footer: {
            Text(
                "The framework decodes; it never fetches. These stand in for payloads "
                    + "your app would download. Set an override in the companion first, "
                    + "then apply one — a local override sits above remote and survives."
            )
        }
    }

    // MARK: - Why each value is what it is

    private var provenance: some View {
        Section {
            ForEach(flags.schema.flags, id: \.key) { entry in
                LabeledContent(entry.key.rawValue) {
                    Text(flags.resolution(for: entry.key, as: entry.valueType).sourceName ?? "default")
                        .foregroundStyle(
                            flags.resolution(for: entry.key, as: entry.valueType).isDefault
                                ? .secondary : .primary
                        )
                }
                .font(.caption.monospaced())
            }
        } header: {
            Text("Where each value came from")
        } footer: {
            Text("resolution(for:) — the answer to “why is this flag false?”")
        }
    }

    // MARK: - Combine

    private var combine: some View {
        Section {
            LabeledContent("new-onboarding changes seen", value: "\(model.onboardingChanges)")
                .font(.caption.monospaced())
        } header: {
            Text("Combine")
        } footer: {
            Text(
                "Counted from $newOnboarding.publisher as changes arrive, whether they "
                    + "come from the companion app or a remote payload."
            )
        }
    }
}
