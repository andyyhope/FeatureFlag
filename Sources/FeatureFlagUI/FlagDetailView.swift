#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// One flag, on a screen of its own.
    ///
    /// Some flags earn that. Not because they are a special kind — the companion reads
    /// them from the published schema like any other and edits them through the same
    /// store — but because of their consequence. A flag that decides which backend the
    /// app talks to moves half the values on the Flags tab with it, and hunting for it in
    /// a list beside forty others undersells that.
    ///
    /// ```swift
    /// FlagCompanionView(appGroup: group, tabs: [
    ///     .overrides,
    ///     .detail(key: "environment", title: "Environment", symbol: "square.stack.3d.up"),
    ///     .flags,
    /// ])
    /// ```
    ///
    /// Which key deserves this is knowledge about a particular app, so it is a parameter.
    /// Point it at any flag and it works the same way.
    public struct FlagDetailView: View {

        @ObservedObject private var store: FlagEditingStore

        private let key: FlagKey
        private let title: String?

        /// - Parameters:
        ///   - store: The same store the other screens use.
        ///   - key: The flag to show. Its own key, as published — `checkout.apple-pay`
        ///     rather than `applePay`.
        ///   - title: The navigation title. Defaults to the flag's description.
        public init(store: FlagEditingStore, key: FlagKey, title: String? = nil) {
            self.store = store
            self.key = key
            self.title = title
        }

        private var entry: FlagSchema.Entry? { store.entry(for: key) }

        public var body: some View {
            NavigationStack {
                Form {
                    if let entry {
                        editor(for: entry)
                        details(for: entry)
                    } else {
                        unavailable
                    }
                }
                .navigationTitle(title ?? entry?.description ?? key.rawValue)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }

        // MARK: - Choosing

        @ViewBuilder
        private func editor(for entry: FlagSchema.Entry) -> some View {
            Section {
                // An enum gets its cases laid out rather than tucked into a menu — the
                // whole point of the screen is that the choice is worth seeing.
                if case let .picker(cases) = entry.editorKind {
                    Picker(entry.description, selection: binding(for: entry)) {
                        ForEach(cases, id: \.self) { value in
                            Text(value.displayString.capitalized).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } else {
                    // Everything else already has a control that suits its type.
                    FlagRowView(store: store, entry: entry)
                }
            } header: {
                Text(entry.description)
            } footer: {
                Text(
                    "Anything you set here stays set. A value set by hand outranks whatever "
                        + "a backend sends, until you reset it."
                )
            }
        }

        private func details(for entry: FlagSchema.Entry) -> some View {
            Section {
                LabeledContent("Key", value: entry.key.rawValue)
                LabeledContent("Default", value: entry.defaultValue.displayString)
                LabeledContent(
                    "Remotely overridable",
                    value: entry.remoteKey.map { "Yes — \($0)" } ?? "No"
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
                        ? "No remote key, so nothing a payload contains can change this "
                            + "flag. For a flag that decides which payload gets fetched, "
                            + "that is deliberate — otherwise the two drive each other."
                        : "This flag carries a remote key, so a payload can change it."
                )
            }
            .font(.callout)
        }

        private var unavailable: some View {
            Section {
                Text("This app publishes no flag called \u{201C}\(key.rawValue)\u{201D}.")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Check the key as the schema publishes it — a nested flag is "
                        + "\u{201C}checkout.apple-pay\u{201D}, not \u{201C}applePay\u{201D}."
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

#endif
