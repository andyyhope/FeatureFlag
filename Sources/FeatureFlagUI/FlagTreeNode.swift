import FeatureFlag

/// One level of the flag tree: the flags declared directly here, and the groups beneath.
///
/// A published `FlagSchema` is deliberately flat — a list of flags, each carrying the
/// property path it sits at — because a flat list is easy to serialise and to validate a
/// payload against. An editor wants the shape back, so that a tree of any depth can be
/// walked one screen at a time rather than poured into one enormous list.
public struct FlagTreeNode: Identifiable, Hashable, Sendable {

    /// Property names from the root. Empty for the root itself.
    public let path: [String]

    /// The group's description, or `nil` at the root.
    public let title: String?

    /// Flags declared directly at this level, in declaration order.
    public let flags: [FlagSchema.Entry]

    /// Groups nested directly beneath, in declaration order.
    public let groups: [FlagTreeNode]

    public var id: String { path.joined(separator: ".") }

    /// Every flag at or below this node.
    public var allFlags: [FlagSchema.Entry] {
        flags + groups.flatMap(\.allFlags)
    }

    /// Whether there is nothing here or anywhere beneath.
    public var isEmpty: Bool {
        flags.isEmpty && groups.allSatisfy(\.isEmpty)
    }
}

extension FlagTreeNode {

    /// Rebuilds the tree a schema flattened.
    ///
    /// Order follows the schema, which follows declaration order, so a tree looks the way
    /// the container that produced it reads.
    public init(schema: FlagSchema) {
        self.init(schema: schema, path: [], title: nil)
    }

    private init(schema: FlagSchema, path: [String], title: String?) {
        self.path = path
        self.title = title
        self.flags = schema.flags.filter { $0.propertyPath.dropLast() == ArraySlice(path) }
        self.groups =
            schema.groups
            .filter { $0.propertyPath.count == path.count + 1 && $0.propertyPath.starts(with: path) }
            .map {
                FlagTreeNode(schema: schema, path: $0.propertyPath, title: $0.description)
            }
    }
}
