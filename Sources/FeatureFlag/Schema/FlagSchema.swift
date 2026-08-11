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
    }

    /// One nested container. Groups namespace their children and nothing else.
    public struct Group: Hashable, Sendable {
        public let propertyPath: [String]
        public let description: String
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

    /// The declared type of every flag, for validating an incoming payload.
    public var valueTypes: [FlagKey: FlagValueType] {
        Dictionary(uniqueKeysWithValues: flags.map { ($0.key, $0.valueType) })
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
        try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .sortedKeys]
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

        self.init(
            formatVersion: version,
            generatedAt: (object["generatedAt"] as? String).flatMap(flagDateFormatter.date(from:))
                ?? Date(timeIntervalSince1970: 0),
            applicationName: object["applicationName"] as? String,
            flags: try flagObjects.map(Entry.init(jsonObject:)),
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
    @discardableResult
    public func write(toDirectory directory: URL) throws -> URL {
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

    /// The shared container for an App Group, or `nil` when the group is missing from
    /// the target's entitlements.
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
