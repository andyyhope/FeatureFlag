import FeatureFlag
import FeatureFlagUI
import SwiftUI

/// The environment flag, on its own, because it is the one that moves everything else.
///
/// It is an ordinary flag — the companion reads it from the published schema like any
/// other, and edits it through the same store. What earns it a tab is not a special type
/// but its consequence: changing it makes the host fetch a different payload, so half
/// the values on the Flags tab move with it.
///
/// Which key is "the environment" is knowledge about a particular app, so it lives here
/// rather than in FeatureFlagUI. Point it at a different key and it works the same way.
struct EnvironmentTab: View {

    @ObservedObject var store: FlagEditingStore

    private let key: FlagKey = "environment"

    private var entry: FlagSchema.Entry? { store.entry(for: key) }

    var body: some View {
        NavigationStack {
            Form {
                if let entry, case let .picker(cases) = entry.editorKind {
                    picker(for: entry, cases: cases)
                    consequences(for: entry)
                } else {
                    unavailable
                }
            }
            .navigationTitle("Environment")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Choosing

    private func picker(for entry: FlagSchema.Entry, cases: [FlagValueBox]) -> some View {
        Section {
            Picker("Environment", selection: binding(for: entry)) {
                ForEach(cases, id: \.self) { value in
                    Text(value.displayString.capitalized).tag(value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(entry.description)
        } footer: {
            Text(
                "Changing this asks the app to fetch that environment's configuration. "
                    + "Anything you have overridden on the Flags tab stays overridden — "
                    + "a value set by hand outranks whatever the backend sends."
            )
        }
    }

    private func consequences(for entry: FlagSchema.Entry) -> some View {
        Section {
            LabeledContent("Key", value: entry.key.rawValue)
            LabeledContent("Default", value: entry.defaultValue.displayString)
            LabeledContent(
                "Remotely overridable",
                value: entry.remoteKey == nil ? "No" : "Yes — \(entry.remoteKey!)"
            )

            if store.isOverridden(entry) {
                Button("Reset to the app's default", role: .destructive) {
                    try? store.reset(entry)
                }
            }
        } header: {
            Text("Details")
        } footer: {
            Text(
                entry.remoteKey == nil
                    ? "No remote key, deliberately. This flag decides which payload gets "
                        + "fetched, so a payload must not be able to decide it back."
                    : "This flag carries a remote key, so a payload can change it — and "
                        + "then change which payload should have been fetched."
            )
        }
        .font(.callout)
    }

    private var unavailable: some View {
        Section {
            Text("This app publishes no flag called “\(key.rawValue)”.")
                .foregroundStyle(.secondary)
        } footer: {
            Text(
                "An environment is an ordinary enum flag. Declare one and it appears here, "
                    + "as well as on the Flags tab."
            )
        }
    }

    private func binding(for entry: FlagSchema.Entry) -> Binding<FlagValueBox> {
        Binding(
            get: { store.value(for: entry) },
            set: { try? store.setValue($0, for: entry) }
        )
    }
}
