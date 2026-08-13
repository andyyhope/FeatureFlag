#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// Everything that has been changed away from what the app ships with, in one place.
    ///
    /// The Flags tab answers "what can I change?". This answers "what *have* I changed?",
    /// which is the question you actually have before filing a bug, handing a device to
    /// someone else, or wondering why a build is behaving oddly. It is also where the
    /// overrides leave the device — as JSON, as a property list, or as a QR code.
    public struct FlagOverridesView: View {

        @ObservedObject private var store: FlagEditingStore
        @State private var sheet: Sheet?
        @State private var problem: String?
        @State private var hasCopiedJSON = false

        private enum Sheet: Identifiable {
            case qrCode
            case importDocument

            var id: Int { hashValue }
        }

        public init(store: FlagEditingStore) {
            self.store = store
        }

        public var body: some View {
            NavigationStack {
                List {
                    if store.overriddenKeys.isEmpty {
                        empty
                    } else {
                        overrides
                        json
                        actions
                    }
                    importSection
                }
                .navigationTitle("Overrides")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .sheet(item: $sheet) { sheet in
                    switch sheet {
                    case .qrCode: FlagQRCodeView(store: store)
                    case .importDocument: FlagImportView(store: store)
                    }
                }
                .alert(
                    "Could not do that",
                    isPresented: Binding(
                        get: { problem != nil },
                        set: { if $0 == false { problem = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(problem ?? "")
                }
            }
        }

        // MARK: - What has changed

        private var empty: some View {
            Section {
                ContentUnavailableMessage(
                    title: "Nothing overridden",
                    message: "Every flag is reporting the value the app was built with."
                )
            }
        }

        private var overrides: some View {
            Section {
                ForEach(overriddenEntries, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.description)
                                Text(entry.key.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Button {
                                try? store.reset(entry)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .buttonStyle(.borderless)
                        }

                        // On its own line, so it has the row's full width. Sharing a
                        // line with the title meant a URL or an array had to shrink to
                        // fit beside it, which is the value you most want to read.
                        Text(store.value(for: entry).displayString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                Text("\(store.overriddenKeys.count) changed")
            } footer: {
                Text("Tap the arrow to put a flag back to the app's default.")
            }
        }

        // MARK: - The document

        private var json: some View {
            Section {
                Text(exportedJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.trailing, 36)
                    .padding(.vertical, 4)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            FlagPasteboard.copy(exportedJSON)
                            withAnimation(.easeOut(duration: 0.15)) { hasCopiedJSON = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                withAnimation(.easeIn(duration: 0.2)) { hasCopiedJSON = false }
                            }
                        } label: {
                            Image(systemName: hasCopiedJSON ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(hasCopiedJSON ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hasCopiedJSON ? "Copied" : "Copy JSON")
                    }
            } header: {
                Text("JSON")
            } footer: {
                Text(
                    "Only overrides travel — the defaults are already in the app. This is "
                        + "what a QR code carries, compressed."
                )
            }
        }

        private var actions: some View {
            Section {
                Button {
                    sheet = .qrCode
                } label: {
                    Label("Show QR code", systemImage: "qrcode")
                }

                ShareLink(item: exportedJSON) {
                    Label("Share JSON", systemImage: "square.and.arrow.up")
                }

                Button {
                    sharePropertyList()
                } label: {
                    Label("Copy property list", systemImage: "doc.on.clipboard")
                }

                Button(role: .destructive) {
                    do { try store.resetAll() } catch { problem = "\(error)" }
                } label: {
                    Label("Reset every override", systemImage: "arrow.uturn.backward")
                }
            }
        }

        private var importSection: some View {
            Section {
                Button {
                    sheet = .importDocument
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text(
                    "Paste an exported document or a scanned code. Import is all or "
                        + "nothing: one unknown key or wrong type rejects the whole thing."
                )
            }
        }

        // MARK: - Helpers

        private var overriddenEntries: [FlagSchema.Entry] {
            store.schema.flags.filter(store.isOverridden)
        }

        private var exportedJSON: String {
            guard let data = try? store.export(as: .json) else { return "{}" }
            return String(decoding: data, as: UTF8.self)
        }

        private func sharePropertyList() {
            do {
                let data = try store.export(as: .plist)
                FlagPasteboard.copy(String(decoding: data, as: UTF8.self))
            } catch {
                problem = "\(error)"
            }
        }
    }

#endif
