import Combine
import FeatureFlag
import Foundation

#if canImport(CoreImage)
    import CoreGraphics
#endif

/// Drives a companion app's editor from a published schema and a shared store.
///
/// It never sees the host app's Swift types. Everything it renders comes from the
/// ``FlagSchema`` the host published; everything it changes goes into a
/// ``MutableFlagValueSource`` the two processes share.
public final class FlagEditingStore: ObservableObject {

    public let schema: FlagSchema

    /// Filters the visible flags by key and description.
    @Published public var searchText: String = ""

    private let source: any MutableFlagValueSource
    private var cancellables: Set<AnyCancellable> = []

    public init(schema: FlagSchema, source: any MutableFlagValueSource) {
        self.schema = schema
        self.source = source

        // Another process editing the same store should update this one live.
        source.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Reads the schema a host app published into an App Group and edits the same
    /// shared suite.
    ///
    /// Throws when the group is missing from this target's entitlements, or when the
    /// host has not published a schema yet.
    public convenience init(appGroup groupIdentifier: String) throws {
        guard let source = UserDefaultsSource(appGroup: groupIdentifier) else {
            throw FlagSchemaError.notPublished
        }
        try self.init(schema: FlagSchema(appGroup: groupIdentifier), source: source)
    }

    // MARK: - Structure

    /// The flags to show, grouped into sections and filtered by ``searchText``.
    public var sections: [FlagSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matches(_ entry: FlagSchema.Entry) -> Bool {
            guard query.isEmpty == false else { return true }
            return entry.key.rawValue.lowercased().contains(query)
                || entry.description.lowercased().contains(query)
        }

        var sections = [FlagSection]()

        let ungrouped = schema.flags.filter { $0.propertyPath.count == 1 }.filter(matches)
        if ungrouped.isEmpty == false {
            sections.append(FlagSection(path: [], title: nil, pathDescription: "", entries: ungrouped))
        }

        for group in schema.groups {
            let entries = schema.flags
                .filter { $0.propertyPath.dropLast() == ArraySlice(group.propertyPath) }
                .filter(matches)
            guard entries.isEmpty == false else { continue }

            sections.append(
                FlagSection(
                    path: group.propertyPath,
                    title: group.description,
                    pathDescription: descriptions(forGroupPath: group.propertyPath)
                        .joined(separator: " › "),
                    entries: entries
                )
            )
        }
        return sections
    }

    /// Every ancestor group's description, so a nested section can show where it sits.
    private func descriptions(forGroupPath path: [String]) -> [String] {
        (1...max(path.count, 1)).compactMap { depth in
            let prefix = Array(path.prefix(depth))
            return schema.groups.first { $0.propertyPath == prefix }?.description
        }
    }

    public func entry(for key: FlagKey) -> FlagSchema.Entry? {
        schema.flags.first { $0.key == key }
    }

    // MARK: - Values

    /// The value in effect: the override if there is one, otherwise the default.
    public func value(for entry: FlagSchema.Entry) -> FlagValueBox {
        usableOverride(for: entry) ?? entry.defaultValue
    }

    public func isOverridden(_ entry: FlagSchema.Entry) -> Bool {
        usableOverride(for: entry) != nil
    }

    /// The stored value, but only if the host app would actually use it.
    ///
    /// A shared suite can hold a stale or hand-edited value of the wrong type, or an
    /// enum case this build no longer has. The host skips those and falls back to its
    /// default, so the editor has to as well — otherwise it shows an override the app
    /// is quietly ignoring, and binds a control to a value it cannot render.
    private func usableOverride(for entry: FlagSchema.Entry) -> FlagValueBox? {
        guard
            let box = source.box(for: entry.key, as: entry.valueType),
            box.matches(entry.valueType)
        else { return nil }

        if let cases = entry.cases, cases.isEmpty == false, cases.contains(box) == false {
            return nil
        }
        return box
    }

    /// Every flag currently overridden, in schema order.
    public var overriddenKeys: [FlagKey] {
        schema.flags.filter(isOverridden).map(\.key)
    }

    public func setValue(_ box: FlagValueBox, for entry: FlagSchema.Entry) throws {
        objectWillChange.send()
        try source.setBox(box, for: entry.key)
    }

    /// Clears one override, so the flag falls back to the host's default.
    public func reset(_ entry: FlagSchema.Entry) throws {
        objectWillChange.send()
        try source.setBox(nil, for: entry.key)
    }

    /// Clears every override this schema knows about.
    ///
    /// Only declared flags are touched — an App Group suite holds more than flags.
    public func resetAll() throws {
        objectWillChange.send()
        for entry in schema.flags {
            try source.setBox(nil, for: entry.key)
        }
    }

    // MARK: - Transport

    public func export(as format: FlagPayloadFormat) throws -> Data {
        var values = [FlagKey: FlagValueBox]()
        for entry in schema.flags where isOverridden(entry) {
            values[entry.key] = value(for: entry)
        }
        return try FlagPayload(values: values).encoded(as: format)
    }

    public func qrCodeString() throws -> String {
        try FlagQRCode.encode(FlagPayload(values: overriddenValues))
    }

    #if canImport(CoreImage)
        public func qrCodeImage(scale: CGFloat = 10) throws -> CGImage {
            try FlagQRCode.image(for: FlagPayload(values: overriddenValues), scale: scale)
        }
    #endif

    private var overriddenValues: [FlagKey: FlagValueBox] {
        var values = [FlagKey: FlagValueBox]()
        for entry in schema.flags where isOverridden(entry) {
            values[entry.key] = value(for: entry)
        }
        return values
    }

    /// Applies an exported document. Strict and all-or-nothing, as everywhere else.
    public func `import`(_ data: Data, as format: FlagPayloadFormat) throws {
        let payload = try FlagPayload.decode(data, as: format, valueTypes: schema.valueTypes)
        try apply(payload)
    }

    public func importQRCode(_ scanned: String) throws {
        try apply(try FlagQRCode.decode(scanned, valueTypes: schema.valueTypes))
    }

    private func apply(_ payload: FlagPayload) throws {
        objectWillChange.send()
        for (key, box) in payload.values {
            try source.setBox(box, for: key)
        }
    }
}

/// One group of flags in the editor.
public struct FlagSection: Identifiable, Sendable {

    /// Property names of the group, empty for the ungrouped flags at the root.
    public let path: [String]

    /// The group's description, or `nil` for the root section.
    public let title: String?

    /// Every ancestor's description, e.g. `Checkout › Express`.
    public let pathDescription: String

    public let entries: [FlagSchema.Entry]

    public var id: String { path.joined(separator: ".") }
}
