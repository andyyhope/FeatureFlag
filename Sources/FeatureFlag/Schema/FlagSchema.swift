import Foundation

/// A description of a host app's flag tree, complete enough for a companion app that
/// has never seen the host's Swift types to render an editor for it.
///
/// This is what decouples the UI. The host publishes one of these into a shared
/// container; the companion reads it and works entirely from the description.
public struct FlagSchema: Sendable, Equatable {

    /// Bumped when the document's shape changes incompatibly.
    public static let currentFormatVersion = 1

    /// The file a schema is published as.
    public static let fileName = "flag-schema.json"

    public let formatVersion: Int
    public let generatedAt: Date

    /// Which app published this, for a companion that can see more than one.
    public let applicationName: String?

    /// Every flag, depth first, in declaration order.
    public let flags: [Entry]

    /// Every group, so the editor can label its sections.
    public let groups: [Group]

    /// One flag.
    public struct Entry: Hashable, Sendable {
        /// The key the flag is stored under, already encoded.
        public let key: FlagKey
        /// Swift property names from the root, for grouping in an editor.
        public let propertyPath: [String]
        public let description: String
        public let valueType: FlagValueType
        public let defaultValue: FlagValueBox
        /// Every case, when the type is a `CaseIterable` enum. Editors show a picker.
        public let cases: [FlagValueBox]?
        public let remoteKey: String?

        public init(
            key: FlagKey,
            propertyPath: [String],
            description: String,
            valueType: FlagValueType,
            defaultValue: FlagValueBox,
            cases: [FlagValueBox]? = nil,
            remoteKey: String? = nil
        ) {
            self.key = key
            self.propertyPath = propertyPath
            self.description = description
            self.valueType = valueType
            self.defaultValue = defaultValue
            self.cases = cases
            self.remoteKey = remoteKey
        }
    }

    /// One nested container. Groups namespace their children and nothing else.
    public struct Group: Hashable, Sendable {
        public let propertyPath: [String]
        public let description: String

        public init(propertyPath: [String], description: String) {
            self.propertyPath = propertyPath
            self.description = description
        }
    }

    /// Describes a container without needing an instance of it.
    public init<Root: FlagContainer>(
        _ type: Root.Type = Root.self,
        keyEncoding: KeyEncoding = .kebabcase,
        applicationName: String? = nil,
        generatedAt: Date = Date()
    ) {
        var flags = [Entry]()
        var groups = [Group]()
        Self.collect(Root.flagDescriptors, keyEncoding: keyEncoding, flags: &flags, groups: &groups)

        self.formatVersion = Self.currentFormatVersion
        self.generatedAt = generatedAt
        self.applicationName = applicationName
        self.flags = flags
        self.groups = groups

        // Two flags sharing a key is a declaration mistake with no runtime remedy: both
        // want the same storage, and quietly letting one win would mean the other never
        // takes effect on any device. Failing here means failing on the first launch of
        // the build that introduced it, rather than later on somebody else's phone.
        precondition(
            duplicateKeyDescription == nil,
            """
            Flags must resolve to unique keys, but \(duplicateKeyDescription ?? ""). \
            Rename one of the properties, or use a KeyEncoding that tells them apart.
            """
        )
    }

    /// Assembles a schema from entries directly.
    ///
    /// Most callers describe a container instead. This exists for the cases that have
    /// no container to describe — a test fixture, or flags defined somewhere other than
    /// a `@FlagContainer`.
    public init(
        flags: [Entry],
        groups: [Group] = [],
        applicationName: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.init(
            formatVersion: Self.currentFormatVersion,
            generatedAt: generatedAt,
            applicationName: applicationName,
            flags: flags,
            groups: groups
        )
    }

    init(formatVersion: Int, generatedAt: Date, applicationName: String?, flags: [Entry], groups: [Group]) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.applicationName = applicationName
        self.flags = flags
        self.groups = groups
    }

    private static func collect(
        _ nodes: [FlagSchemaNode],
        keyEncoding: KeyEncoding,
        flags: inout [Entry],
        groups: inout [Group]
    ) {
        for node in nodes {
            switch node {
            case let .flag(descriptor):
                flags.append(
                    Entry(
                        key: keyEncoding.key(for: descriptor.keyPath),
                        propertyPath: descriptor.keyPath.propertyNames,
                        description: descriptor.description,
                        valueType: descriptor.valueType,
                        defaultValue: descriptor.defaultValue,
                        cases: descriptor.cases,
                        remoteKey: descriptor.remoteKey
                    )
                )

            case let .group(group):
                groups.append(
                    Group(
                        propertyPath: group.keyPath.propertyNames,
                        description: group.description
                    )
                )
                collect(group.children, keyEncoding: keyEncoding, flags: &flags, groups: &groups)
            }
        }
    }

    /// Flags that resolve to the same key, mapped to the property paths that produced
    /// them. Empty for any well-formed tree.
    ///
    /// Collisions are easier to write than they look: `useHTTPSOnly` and `useHttpsOnly`
    /// both kebabcase to `use-https-only`, and any ``KeyEncoding`` that maps two names
    /// onto one does it far more readily.
    public var duplicateKeys: [FlagKey: [[String]]] {
        Self.duplicateKeys(in: flags)
    }

    /// Every collision as one readable clause, or `nil` when there are none.
    public var duplicateKeyDescription: String? {
        let duplicates = duplicateKeys
        guard duplicates.isEmpty == false else { return nil }

        return
            duplicates
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { key, paths in
                let names = paths.map { $0.joined(separator: ".") }.joined(separator: " and ")
                return "'\(key.rawValue)' is claimed by \(names)"
            }
            .joined(separator: "; ")
    }

    static func duplicateKeys(in flags: [Entry]) -> [FlagKey: [[String]]] {
        var paths = [FlagKey: [[String]]]()
        for entry in flags {
            paths[entry.key, default: []].append(entry.propertyPath)
        }
        return paths.filter { $0.value.count > 1 }
    }

    /// The declared type of every flag, for validating an incoming payload.
    ///
    /// Deliberately tolerant of a key appearing twice — the first wins. A schema built
    /// from a container cannot contain duplicates, but one decoded from a document or
    /// assembled by hand can, and this is reached by every import and by the companion's
    /// editor, where trapping would turn a bad document into a crash.
    public var valueTypes: [FlagKey: FlagValueType] {
        Dictionary(flags.map { ($0.key, $0.valueType) }, uniquingKeysWith: { first, _ in first })
    }

    /// The permitted values of every enum flag, for validating an incoming payload.
    ///
    /// Flags that are not enums are absent rather than present and empty, so a caller
    /// can treat "no entry" as "anything of the right type will do".
    public var valueCases: [FlagKey: [FlagValueBox]] {
        var result = [FlagKey: [FlagValueBox]]()
        for entry in flags {
            guard let cases = entry.cases, cases.isEmpty == false else { continue }
            // First wins, as in `valueTypes`, so a duplicated key cannot trap here.
            if result[entry.key] == nil { result[entry.key] = cases }
        }
        return result
    }
}

public enum FlagSchemaError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case malformed(String)
    case notPublished
}

// MARK: - JSON

extension FlagSchema {

    public func jsonData() throws -> Data {
        // A non-finite default would make JSONSerialization raise an Objective-C
        // exception, killing the process instead of throwing.
        if let entry = flags.first(where: { $0.defaultValue.containsNonFiniteNumber }) {
            throw FlagSerializationError.nonFiniteNumber(entry.key)
        }
        return try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "formatVersion": formatVersion,
            "generatedAt": flagDateFormatter.string(from: generatedAt),
            "flags": flags.map(\.jsonObject),
            "groups": groups.map(\.jsonObject),
        ]
        object["applicationName"] = applicationName
        return object
    }

    public init(jsonData data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlagSchemaError.malformed("not a JSON object")
        }
        try self.init(jsonObject: object)
    }

    init(jsonObject object: [String: Any]) throws {
        guard let version = object["formatVersion"] as? Int else {
            throw FlagSchemaError.malformed("missing formatVersion")
        }
        guard version == Self.currentFormatVersion else {
            throw FlagSchemaError.unsupportedFormatVersion(version)
        }
        guard let flagObjects = object["flags"] as? [[String: Any]] else {
            throw FlagSchemaError.malformed("missing flags")
        }

        let entries = try flagObjects.map(Entry.init(jsonObject:))

        // A published document naming one key twice describes an editor with two rows
        // fighting over the same storage. Saying so beats rendering it.
        if let collision = Self.duplicateKeys(in: entries).keys.sorted(by: {
            $0.rawValue < $1.rawValue
        }).first {
            throw FlagSchemaError.malformed("more than one flag uses the key '\(collision)'")
        }

        self.init(
            formatVersion: version,
            generatedAt: (object["generatedAt"] as? String).flatMap(flagDateFormatter.date(from:))
                ?? Date(timeIntervalSince1970: 0),
            applicationName: object["applicationName"] as? String,
            flags: entries,
            groups: (object["groups"] as? [[String: Any]] ?? []).compactMap(
                Group.init(jsonObject:)
            )
        )
    }
}

extension FlagSchema.Entry {

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "key": key.rawValue,
            "propertyPath": propertyPath,
            "description": description,
            "valueType": valueType.typeName,
            "defaultValue": defaultValue.jsonValue,
        ]
        object["cases"] = cases?.map(\.jsonValue)
        object["remoteKey"] = remoteKey
        return object
    }

    init(jsonObject object: [String: Any]) throws {
        guard
            let key = object["key"] as? String,
            let typeName = object["valueType"] as? String,
            let valueType = FlagValueType(typeName: typeName)
        else {
            throw FlagSchemaError.malformed("flag entry is missing a key or value type")
        }
        guard
            let defaultObject = object["defaultValue"],
            let defaultValue = FlagValueBox(jsonValue: defaultObject, as: valueType)
        else {
            throw FlagSchemaError.malformed("flag '\(key)' has a default that is not a \(typeName)")
        }

        self.key = FlagKey(key)
        self.propertyPath = object["propertyPath"] as? [String] ?? [key]
        self.description = object["description"] as? String ?? ""
        self.valueType = valueType
        self.defaultValue = defaultValue
        self.cases = (object["cases"] as? [Any])?.compactMap {
            FlagValueBox(jsonValue: $0, as: valueType)
        }
        self.remoteKey = object["remoteKey"] as? String
    }
}

extension FlagSchema.Group {

    var jsonObject: [String: Any] {
        ["propertyPath": propertyPath, "description": description]
    }

    init?(jsonObject object: [String: Any]) {
        guard let propertyPath = object["propertyPath"] as? [String] else { return nil }
        self.propertyPath = propertyPath
        self.description = object["description"] as? String ?? ""
    }
}

// MARK: - Publishing

extension FlagSchema {

    /// Writes the schema into a directory, where a companion app can find it.
    ///
    /// The directory is created if it does not exist. An App Group container exists
    /// already on iOS, but on unsandboxed macOS the path is only realised on first use.
    @discardableResult
    public func write(toDirectory directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(Self.fileName)
        try jsonData().write(to: url, options: .atomic)
        return url
    }

    /// Reads a schema a host app published.
    public init(contentsOfDirectory directory: URL) throws {
        let url = directory.appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw FlagSchemaError.notPublished
        }
        try self.init(jsonData: data)
    }

    /// The shared container for an App Group.
    ///
    /// Returns `nil` where the platform checks the group against the process's
    /// entitlements — iOS, and sandboxed macOS. Unsandboxed macOS performs no such
    /// check and hands back a constructed path under `~/Library/Group Containers`
    /// whether or not the group exists, so a non-`nil` result is not proof the group is
    /// configured correctly.
    public static func containerURL(forAppGroup groupIdentifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// Reads the schema a host app published into an App Group container.
    public init(appGroup groupIdentifier: String) throws {
        guard let container = Self.containerURL(forAppGroup: groupIdentifier) else {
            throw FlagSchemaError.notPublished
        }
        try self.init(contentsOfDirectory: container)
    }
}
