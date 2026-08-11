/// Declares a feature flag.
///
/// ```swift
/// @Flag(default: false, description: "New onboarding")
/// var newOnboarding: Bool
/// ```
///
/// Reading the property resolves the value through the container's lookup, falling
/// back to `default` when nothing is stored — or when what is stored has the wrong
/// type, since a malformed store should never crash a running app.
///
/// The projected value (`$newOnboarding`) exposes the flag's key and metadata.
@propertyWrapper
public struct Flag<Value: FlagValue>: Sendable {

    /// The key this flag resolves against, already encoded.
    public let key: FlagKey

    /// The flag's position in its container tree, as raw property names.
    public let keyPath: FlagKeyPath

    /// Used when no source supplies a usable value.
    public let defaultValue: Value

    /// Human-readable explanation of what the flag does.
    public let flagDescription: String

    /// Dot path into a remote payload, if this flag can be remotely overridden.
    public let remoteKey: String?

    private let lookup: (any FlagLookup)?

    /// Declares a flag.
    ///
    /// `lookup` and `keyPath` are supplied by generated container code. Omitting them
    /// yields a detached flag that always reports its default, which is what makes
    /// previews and unit tests work without a tower.
    public init(
        default defaultValue: Value,
        description: String,
        remoteKey: String? = nil,
        lookup: (any FlagLookup)? = nil,
        keyPath: FlagKeyPath = .root
    ) {
        self.defaultValue = defaultValue
        self.flagDescription = description
        self.remoteKey = remoteKey
        self.lookup = lookup
        self.keyPath = keyPath
        self.key = (lookup?.keyEncoding ?? .kebabcase).key(for: keyPath)
    }

    public var wrappedValue: Value {
        guard let box = lookup?.box(for: key) else { return defaultValue }
        return Value(box: box) ?? defaultValue
    }

    public var projectedValue: FlagAccessor<Value> {
        FlagAccessor(
            key: key,
            keyPath: keyPath,
            description: flagDescription,
            defaultValue: defaultValue,
            remoteKey: remoteKey
        )
    }
}

/// The projected value of a ``Flag``, reached with `$`.
public struct FlagAccessor<Value: FlagValue>: Sendable {

    /// The key this flag resolves against, already encoded.
    public let key: FlagKey

    /// The flag's position in its container tree, as raw property names.
    public let keyPath: FlagKeyPath

    /// Human-readable explanation of what the flag does.
    public let description: String

    /// Used when no source supplies a usable value.
    public let defaultValue: Value

    /// Dot path into a remote payload, if this flag can be remotely overridden.
    public let remoteKey: String?
}
