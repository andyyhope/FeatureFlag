import Combine
import Foundation

/// Reads feature flags, resolving each one through an ordered stack of sources.
///
/// ```swift
/// let pole = FlagPole(
///     AppFlags.self,
///     sources: [UserDefaultsSource(appGroup: "group.com.example.flags")!, remote]
/// )
///
/// if pole.checkout.applePay { ... }
/// ```
///
/// The stack order *is* the precedence. The recommended arrangement puts local
/// overrides above remote payloads, so a value set by hand in the companion app stays
/// set until it is explicitly cleared.
///
/// Reads are lock-protected and safe from any thread — apps read flags off the main
/// thread constantly. Only `objectWillChange` is delivered on the main thread, so
/// SwiftUI observation is always correct.
@dynamicMemberLookup
public final class FlagPole<Root: FlagContainer>: ObservableObject, @unchecked Sendable {

    /// The flag tree. Use this to reach projected values: `pole.flags.$newOnboarding`.
    public let flags: Root

    private let resolver: FlagResolver
    private var cancellables: Set<AnyCancellable> = []

    public init(
        _ rootType: Root.Type = Root.self,
        sources: [any FlagValueSource],
        keyEncoding: KeyEncoding = .kebabcase
    ) {
        let resolver = FlagResolver(sources: sources, keyEncoding: keyEncoding)
        self.resolver = resolver
        self.flags = Root(_lookup: resolver, _keyPrefix: .root)

        resolver.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Reads a flag without going through ``flags``: `pole.newOnboarding`.
    public subscript<Value>(dynamicMember keyPath: KeyPath<Root, Value>) -> Value {
        flags[keyPath: keyPath]
    }

    /// How property-name paths become storage keys.
    public var keyEncoding: KeyEncoding { resolver.keyEncoding }

    // MARK: - Explaining a value

    /// Which source supplied a flag's current value, and what it was.
    ///
    /// This is the answer to "why is this flag false?".
    public func resolution<Value>(for accessor: FlagAccessor<Value>) -> FlagResolution {
        let resolution = resolver.resolution(for: accessor.key, as: Value.flagValueType)
        guard resolution.isDefault else { return resolution }

        // The resolver walks sources and so cannot know compiled defaults. Filling one
        // in here keeps `box` meaning "the value in effect" in every case.
        return FlagResolution(key: accessor.key, sourceName: nil, box: accessor.defaultValue.box)
    }

    // MARK: - Overrides

    /// Every flag this pole knows about, flattened out of the container tree.
    public var descriptors: [FlagDescriptor] { Root.flagDescriptors.flattened() }

    /// The key each flag resolves against, in declaration order.
    public var keys: [FlagKey] { descriptors.map { keyEncoding.key(for: $0.keyPath) } }

    /// Every flag some source supplies a value for — everything that is not simply its
    /// compiled default.
    public var overrides: [FlagKey: FlagValueBox] {
        var result = [FlagKey: FlagValueBox]()
        for descriptor in descriptors {
            let key = keyEncoding.key(for: descriptor.keyPath)
            if let box = resolver.box(for: key, as: descriptor.valueType) {
                result[key] = box
            }
        }
        return result
    }

    /// Writes an override to the highest-priority source that accepts writes.
    public func setOverride<Value>(_ value: Value, for accessor: FlagAccessor<Value>) throws {
        try resolver.setOverride(value.box, for: accessor.key)
    }

    /// Writes an already-boxed override. Used by import, which works from a schema
    /// rather than from typed accessors.
    public func setOverride(_ box: FlagValueBox?, for key: FlagKey) throws {
        try resolver.setOverride(box, for: key)
    }

    /// What the source writes go to currently holds for a key, ignoring the sources
    /// beneath it. Used to undo a partly applied import.
    public func currentOverride(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        resolver.currentOverride(for: key, as: type)
    }

    /// Clears a flag's override, restoring whatever the sources beneath it say.
    public func removeOverride<Value>(for accessor: FlagAccessor<Value>) throws {
        try resolver.setOverride(nil, for: accessor.key)
    }

    /// Clears overrides for every flag this pole knows about.
    ///
    /// Only declared flags are touched, so unrelated values sharing the store — an
    /// App Group suite holds more than flags — are left alone.
    public func removeAllOverrides() throws {
        for key in keys {
            try resolver.setOverride(nil, for: key)
        }
    }
}
