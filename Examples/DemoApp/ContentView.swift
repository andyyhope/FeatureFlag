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
                paymentMethods
                remoteConfiguration
                provenance
                signals
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
                "Changing this loads two layers for the environment: a config bundled "
                    + "in the app, then one fetched for it, remote winning. The flag "
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

    /// A record flag read the way an app would actually read one: typed, and used.
    private var paymentMethods: some View {
        Section {
            // By position, not by name: two records can share a name — the companion
            // can add one and leave it blank — and a duplicated ForEach id makes
            // SwiftUI drop rows.
            ForEach(Array(flags.paymentMethods.values.enumerated()), id: \.offset) { _, method in
                LabeledContent {
                    Text(method.enabled ? "on" : "off")
                        .foregroundStyle(method.enabled ? .green : .secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.name.isEmpty ? "Untitled" : method.name)
                        Text("\(method.kind.rawValue) · min \(method.minimumSpend, format: .number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Payment methods")
        } footer: {
            Text(
                "A list of records. Edit them field by field in the companion app, or "
                    + "switch environment above to have a payload replace the whole list."
            )
        }
    }

    // MARK: - Remote payloads

    private var remoteConfiguration: some View {
        Section {
            payloadButton(.experiments)
            payloadButton(.experimentsWithATypo)
            payloadButton(.malformed)

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
                    + "applePay beside it is not applied either. Clearing the remote "
                    + "layer falls back to the bundled local config, not to raw "
                    + "defaults — watch the sources below change from Remote to Local."
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
            Text(
                "resolution(for:) — which layer each value came from. Highest first: a "
                    + "by-hand override (Companion), the fetched Remote config, the "
                    + "bundled Local config, then the compiled default."
            )
        }
    }

    /// One payload, offered as a button. The broken ones are marked, so a rejection
    /// reads as the point of the exercise rather than as the demo being wrong.
    private func payloadButton(_ configuration: RemoteConfiguration) -> some View {
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
                if configuration.isDeliberatelyBroken {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signals

    private var signals: some View {
        Section {
            LabeledContent("Last signal received", value: model.lastSignal ?? "—")
                .font(.caption.monospaced())
            LabeledContent("Caches purged", value: "\(model.purgedCaches)")
                .font(.caption.monospaced())

            if model.awaitingRelaunch {
                Text("Everything was purged. It is rebuilt at launch, so this screen "
                    + "will not look any different until the app starts again — which "
                    + "is what that signal's requiresRestart is for.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Signals from the companion")
        } footer: {
            Text(
                "The companion can ask this app to do something, not only change what it "
                    + "reads. iOS will not wake a closed app for another app, so a signal "
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
