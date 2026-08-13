// The editor is an iOS and macOS surface. watchOS has no Menu, TextEditor or
// bordered text field, and a flag-editing companion on a watch is not a real use case;
// tvOS has no text entry worth the name. The core FeatureFlag module supports every
// platform — this is only the UI.
#if os(iOS) || os(macOS)

import FeatureFlag
import SwiftUI

/// The companion app's editor: every flag the host published, grouped, searchable and
/// editable.
///
/// Nothing here knows the host app's Swift types. It renders whatever schema it is
/// given, so one companion build works for any app that publishes one.
public struct FlagBrowserView: View {

    @ObservedObject private var store: FlagEditingStore
    public init(store: FlagEditingStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                if store.searchText.isEmpty {
                    tree
                } else {
                    matches
                }

                if store.sections.isEmpty {
                    ContentUnavailableMessage(
                        title: store.searchText.isEmpty ? "No flags" : "No matches",
                        message: store.searchText.isEmpty
                            ? "The app has not published any flags yet."
                            : "No flag matches \u{201C}\(store.searchText)\u{201D}."
                    )
                }
            }
            .searchable(text: $store.searchText, prompt: "Search flags")
            .navigationTitle(store.schema.applicationName ?? "Feature Flags")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// Flags declared at the root, then a way into each group.
    @ViewBuilder
    private var tree: some View {
        let root = store.tree

        if root.flags.isEmpty == false {
            Section {
                ForEach(root.flags, id: \.key) { entry in
                    FlagRowView(store: store, entry: entry)
                }
            }
        }

        if root.groups.isEmpty == false {
            Section(root.flags.isEmpty ? "" : "Groups") {
                ForEach(root.groups) { node in
                    FlagGroupLink(store: store, node: node)
                }
            }
        }
    }

    /// Searching flattens the tree. Someone looking for a key by name does not want to
    /// guess which group it was filed under.
    @ViewBuilder
    private var matches: some View {
        ForEach(store.sections) { section in
            Section {
                ForEach(section.entries, id: \.key) { entry in
                    FlagRowView(store: store, entry: entry)
                }
            } header: {
                if let title = section.title {
                    Text(section.path.count > 1 ? section.pathDescription : title)
                }
            }
        }
    }
}

/// Shows the current overrides as a scannable code.
public struct FlagQRCodeView: View {

    @ObservedObject private var store: FlagEditingStore
    @Environment(\.dismiss) private var dismiss

    public init(store: FlagEditingStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if canImport(CoreImage)
                    if let image = try? store.qrCodeImage(scale: 8) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320)
                            .accessibilityLabel("QR code containing \(store.overriddenKeys.count) overrides")
                    } else {
                        Text(unavailableMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                #endif

                Text("\(store.overriddenKeys.count) override(s)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Scan to copy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The size limit is the failure people actually hit, so say what exceeded it and
    /// what to do rather than "could not generate".
    private var unavailableMessage: String {
        do {
            _ = try store.qrCodeString()
            return "Could not render the code."
        } catch let FlagQRCodeError.payloadTooLarge(bytes, limit, overrideCount) {
            return """
                \(overrideCount) overrides need \(bytes) characters, and a QR code holds \
                \(limit). Reset a few, or export JSON instead.
                """
        } catch {
            return "\(error)"
        }
    }
}

/// Pastes in an exported document or a scanned code.
public struct FlagImportView: View {

    @ObservedObject private var store: FlagEditingStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?

    public init(store: FlagEditingStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste exported JSON, or the contents of a scanned flag code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 160)

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: performImport)
                        .disabled(text.isEmpty)
                }
            }
        }
    }

    private func performImport() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.hasPrefix(FlagQRCode.prefix) {
                try store.importQRCode(trimmed)
            } else {
                try store.import(Data(trimmed.utf8), as: .json)
            }
            dismiss()
        } catch {
            problem = describe(error)
        }
    }

    /// Import is all-or-nothing, so the message needs to list everything wrong at once.
    private func describe(_ error: Error) -> String {
        switch error {
        case let FlagImportError.rejected(problems):
            return problems
                .map { problem in
                    switch problem.kind {
                    case .unknownKey: return "\(problem.key): not a flag in this app"
                    case .typeMismatch: return "\(problem.key): wrong type"
                    }
                }
                .joined(separator: "\n")
        case let FlagImportError.unsupportedFormatVersion(version):
            return "This document was written by a newer version (format \(version))."
        case FlagImportError.malformed:
            return "That is not a flag document."
        default:
            return "\(error)"
        }
    }
}

/// Small stand-in so the browser compiles on the deployment targets this package
/// supports, where `ContentUnavailableView` is not available.
struct ContentUnavailableMessage: View {

    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#endif
