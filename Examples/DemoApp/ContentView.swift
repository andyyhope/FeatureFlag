import FeatureFlag
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var model: DemoModel

    private var flags: FlagPole<AppFlags> { model.flags }

    var body: some View {
        NavigationStack {
            List {
                environment
                liveValues
                remoteConfiguration
                provenance
                events
                combine
            }
            .navigationTitle("Demo")
        }
    }

    // MARK: - Environment

    private var environment: some View {
        Section {
            Picker("Environment", selection: $model.environment) {
                ForEach(DemoEnvironment.allCases, id: \.self) { environment in
                    Text(environment.rawValue.capitalized).tag(environment)
                }
            }
            .pickerStyle(.segmented)

            if let applied = model.appliedConfiguration {
                LabeledContent("Payload applied", value: applied.name)
                    .font(.caption.monospaced())
            }
        } header: {
            Text("Environment")
        } footer: {
            Text(
                "Changing this fetches and applies that environment's payload. The flag "
                    + "carries no remoteKey, so nothing a payload contains can change it "
                    + "back — otherwise the two would drive each other in a loop."
            )
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
            Button {
                model.apply(.malformed)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RemoteConfiguration.malformed.name)
                        Text(RemoteConfiguration.malformed.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .buttonStyle(.plain)

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
            Text("Rejecting a bad payload")
        } footer: {
            Text(
                "One field of the wrong type rejects the whole payload — the valid "
                    + "applePay beside it is not applied either. Nothing runs on half a "
                    + "configuration."
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

    // MARK: - Events

    private var events: some View {
        Section {
            LabeledContent("Last event received", value: model.lastEvent?.rawValue ?? "—")
                .font(.caption.monospaced())
        } header: {
            Text("Events from the companion")
        } footer: {
            Text(
                "The companion can ask this app to do something, not only change what it "
                    + "reads. iOS will not wake a closed app for another app, so an event "
                    + "sent while this one is not running is lost rather than queued."
            )
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
