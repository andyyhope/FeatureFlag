#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// One level of the flag tree: its own flags, and a way into the groups beneath.
    ///
    /// Pushing rather than inlining is what keeps a large tree usable — a hundred flags
    /// under six groups is a scroll you give up on, but six rows is a menu.
    public struct FlagGroupView: View {

        @ObservedObject private var store: FlagEditingStore
        private let node: FlagTreeNode

        public init(store: FlagEditingStore, node: FlagTreeNode) {
            self.store = store
            self.node = node
        }

        public var body: some View {
            List {
                if node.flags.isEmpty == false {
                    Section {
                        ForEach(node.flags, id: \.key) { entry in
                            FlagRowView(store: store, entry: entry)
                        }
                    }
                }

                if node.groups.isEmpty == false {
                    Section(node.flags.isEmpty ? "" : "Groups") {
                        ForEach(node.groups) { child in
                            FlagGroupLink(store: store, node: child)
                        }
                    }
                }
            }
            .navigationTitle(node.title ?? "Flags")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// A row that leads into a group, showing how much is inside and how much of it has
    /// been changed.
    struct FlagGroupLink: View {

        @ObservedObject var store: FlagEditingStore
        let node: FlagTreeNode

        var body: some View {
            NavigationLink {
                FlagGroupView(store: store, node: node)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.title ?? node.id)
                        Text("\(node.allFlags.count) flag\(node.allFlags.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    let changed = store.overriddenCount(in: node)
                    if changed > 0 {
                        Text("\(changed)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

#endif
