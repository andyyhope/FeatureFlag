/// Everything about one flag that an editor or a remote mapper needs, available
/// without an instance of the container that declares it.
public struct FlagDescriptor: Hashable, Sendable {

    /// The Swift property name, as written.
    public let propertyName: String

    /// Position in the container tree. Encode it to get the storage key.
    public let keyPath: FlagKeyPath

    /// Human-readable explanation of what the flag does.
    public let description: String

    /// The declared Swift type, for editor selection and strict remote validation.
    public let valueType: FlagValueType

    /// Used when no source supplies a usable value.
    public let defaultValue: FlagValueBox

    /// Every case, when the value type is a `CaseIterable` enum. Editors render a
    /// picker rather than a free-text field when this is present.
    public let cases: [FlagValueBox]?

    /// Dot path into a remote payload. `nil` means the flag is not remotely
    /// overridable.
    public let remoteKey: String?

    public init(
        propertyName: String,
        keyPath: FlagKeyPath,
        description: String,
        valueType: FlagValueType,
        defaultValue: FlagValueBox,
        cases: [FlagValueBox]? = nil,
        remoteKey: String? = nil
    ) {
        self.propertyName = propertyName
        self.keyPath = keyPath
        self.description = description
        self.valueType = valueType
        self.defaultValue = defaultValue
        self.cases = cases
        self.remoteKey = remoteKey
    }
}

/// A nested container, which namespaces its children and nothing more. A group has no
/// value of its own and never gates what it contains.
public struct FlagGroupDescriptor: Hashable, Sendable {

    /// The Swift property name, as written.
    public let propertyName: String

    /// Position in the container tree.
    public let keyPath: FlagKeyPath

    /// Human-readable explanation of what the group covers.
    public let description: String

    /// Flags and further groups beneath this one, already re-rooted under its path.
    public let children: [FlagSchemaNode]

    public init(
        propertyName: String,
        keyPath: FlagKeyPath,
        description: String,
        children: [FlagSchemaNode]
    ) {
        self.propertyName = propertyName
        self.keyPath = keyPath
        self.description = description
        self.children = children
    }
}

/// One entry in a container's shape: either a flag or a nested group.
public enum FlagSchemaNode: Hashable, Sendable {

    case flag(FlagDescriptor)
    case group(FlagGroupDescriptor)

    /// The Swift property name, as written.
    public var propertyName: String {
        switch self {
        case let .flag(descriptor): return descriptor.propertyName
        case let .group(group): return group.propertyName
        }
    }

    /// Position in the container tree.
    public var keyPath: FlagKeyPath {
        switch self {
        case let .flag(descriptor): return descriptor.keyPath
        case let .group(group): return group.keyPath
        }
    }

    /// Re-roots this node, and everything beneath it, under `component`.
    ///
    /// A container describes itself relative to its own root, so a parent has to
    /// re-root a child group's descriptors when it embeds them.
    public func prefixed(by component: String) -> FlagSchemaNode {
        switch self {
        case let .flag(descriptor):
            return .flag(descriptor.prefixed(by: component))
        case let .group(group):
            return .group(group.prefixed(by: component))
        }
    }
}

extension Array where Element == FlagSchemaNode {

    /// Every flag in the tree, depth first, in declaration order.
    ///
    /// Group children are already re-rooted, so the key paths that come back are
    /// complete.
    public func flattened() -> [FlagDescriptor] {
        flatMap { node -> [FlagDescriptor] in
            switch node {
            case let .flag(descriptor): return [descriptor]
            case let .group(group): return group.children.flattened()
            }
        }
    }
}

extension FlagDescriptor {

    func prefixed(by component: String) -> FlagDescriptor {
        FlagDescriptor(
            propertyName: propertyName,
            keyPath: keyPath.prepending(component),
            description: description,
            valueType: valueType,
            defaultValue: defaultValue,
            cases: cases,
            remoteKey: remoteKey
        )
    }
}

extension FlagGroupDescriptor {

    func prefixed(by component: String) -> FlagGroupDescriptor {
        FlagGroupDescriptor(
            propertyName: propertyName,
            keyPath: keyPath.prepending(component),
            description: description,
            children: children.map { $0.prefixed(by: component) }
        )
    }
}
