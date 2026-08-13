import Combine
import Foundation

/// Turns a backend's payload into flag values.
///
/// The built-in ``DotPathMapper`` reads each flag's `remoteKey`. Implement this only
/// when a payload's shape cannot be addressed by a path — a list of records, say.
public protocol RemoteOverrideMapper: Sendable {

    /// Picks flag values out of a decoded payload.
    ///
    /// Values are returned raw; validating them against each flag's declared type is
    /// the source's job, so a mapper never has to think about boxing.
    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue]
}

/// Reads each flag's `remoteKey` as a dot path into the payload.
///
/// ```swift
/// @Flag(default: false, description: "New checkout",
///       remoteKey: "featureToggles.checkout.v2")
/// var newCheckout: Bool
/// ```
///
/// Flags without a `remoteKey` are not remotely overridable at all.
public struct DotPathMapper: RemoteOverrideMapper {

    public init() {}

    public func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        var result = [FlagKey: RemoteValue]()
        for entry in schema.flags {
            guard let remoteKey = entry.remoteKey else { continue }
            guard let found = value.value(atPath: remoteKey), found != .null else { continue }
            result[entry.key] = found
        }
        return result
    }
}

/// Something wrong with one value in a remote payload.
public struct RemoteOverrideProblem: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        /// The value is not of the flag's declared type.
        case typeMismatch
        /// The value is not one of the enum's cases.
        case unknownCase
        /// The mapper produced a key no flag in this app has.
        ///
        /// Unlike the identically named case on ``FlagImportProblem``, this one is not
        /// a data problem. ``DotPathMapper`` cannot cause it, since it only ever emits
        /// keys it read from the schema — so reaching it means a custom
        /// ``RemoteOverrideMapper`` returned a key that does not exist, which is a bug
        /// in that mapper rather than anything the backend sent.
        ///
        /// It is reported rather than skipped because silently doing nothing would look
        /// exactly like a backend that sent no overrides at all.
        case unknownKey
    }

    public let key: FlagKey
    public let remoteKey: String
    public let kind: Kind

    public init(key: FlagKey, remoteKey: String, kind: Kind) {
        self.key = key
        self.remoteKey = remoteKey
        self.kind = kind
    }
}

public enum RemoteOverrideError: Error, Equatable {
    case malformed(String)

    /// Every problem found, and nothing applied. One bad field from a backend must not
    /// leave an app running on half a configuration.
    case rejected([RemoteOverrideProblem])
}

public struct RemoteApplyResult: Sendable, Equatable {
    public let appliedKeys: [FlagKey]

    /// Flags that declare a `remoteKey` the payload did not mention. They keep falling
    /// through to whatever sits below this source.
    public let absentKeys: [FlagKey]
}

/// Holds the values from the most recent remote payload.
///
/// This source decodes; it never fetches. Your app gets configuration however it likes
/// — URLSession, a CDN, Firebase, a file shipped in the bundle — and hands the bytes
/// over. No networking, auth, retry or cache invalidation lives in a flag library.
///
/// ```swift
/// let remote = RemoteOverrideSource(AppFlags.self)
/// let pole = FlagPole(AppFlags.self, sources: [local, remote])
///
/// let data = try await fetchConfiguration()
/// try remote.apply(data, format: .json)
/// ```
public final class RemoteOverrideSource: FlagValueSource, @unchecked Sendable {

    public let sourceName: String

    private let schema: FlagSchema
    private let mapper: any RemoteOverrideMapper
    private let lock = NSLock()
    private var values: [FlagKey: FlagValueBox] = [:]
    private let subject = PassthroughSubject<FlagChange, Never>()

    public init(
        schema: FlagSchema,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        name: String = "Remote"
    ) {
        self.schema = schema
        self.mapper = mapper
        self.sourceName = name
    }

    /// Builds a source for a container, describing it with the same key encoding the
    /// pole will use.
    public convenience init<Root: FlagContainer>(
        _ type: Root.Type = Root.self,
        keyEncoding: KeyEncoding = .kebabcase,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        name: String = "Remote"
    ) {
        self.init(
            schema: FlagSchema(Root.self, keyEncoding: keyEncoding),
            mapper: mapper,
            name: name
        )
    }

    public func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Applying a payload

    /// Decodes a payload and replaces everything this source holds.
    ///
    /// Strict and all-or-nothing: every value is checked against its flag's declared
    /// type, and against the enum's cases where there are any, before anything is
    /// applied.
    @discardableResult
    public func apply(_ data: Data, format: FlagPayloadFormat) throws -> RemoteApplyResult {
        let object: Any
        switch format {
        case .json:
            guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
                throw RemoteOverrideError.malformed("not valid JSON")
            }
            object = parsed
        case .plist:
            guard
                let parsed = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                )
            else { throw RemoteOverrideError.malformed("not a valid property list") }
            object = parsed
        }
        return try apply(RemoteValue(deserialised: object))
    }

    /// Applies an already-decoded payload.
    @discardableResult
    public func apply(_ value: RemoteValue) throws -> RemoteApplyResult {
        let mapped = try mapper.map(value, schema: schema)
        let entries = Dictionary(uniqueKeysWithValues: schema.flags.map { ($0.key, $0) })

        var boxes = [FlagKey: FlagValueBox]()
        var problems = [RemoteOverrideProblem]()

        for (key, remoteValue) in mapped {
            guard let entry = entries[key] else {
                problems.append(
                    RemoteOverrideProblem(key: key, remoteKey: key.rawValue, kind: .unknownKey)
                )
                continue
            }

            guard let box = remoteValue.box(as: entry.valueType) else {
                problems.append(
                    RemoteOverrideProblem(
                        key: key,
                        remoteKey: entry.remoteKey ?? key.rawValue,
                        kind: .typeMismatch
                    )
                )
                continue
            }

            // Enums declare their cases, so a backend sending a value the app cannot
            // represent is caught here rather than silently falling back at read time.
            if let cases = entry.cases, !cases.contains(box) {
                problems.append(
                    RemoteOverrideProblem(
                        key: key,
                        remoteKey: entry.remoteKey ?? key.rawValue,
                        kind: .unknownCase
                    )
                )
                continue
            }

            boxes[key] = box
        }

        guard problems.isEmpty else {
            throw RemoteOverrideError.rejected(
                problems.sorted { $0.key.rawValue < $1.key.rawValue }
            )
        }

        lock.lock()
        values = boxes
        lock.unlock()
        subject.send(.all)

        let remotelyOverridable = schema.flags.filter { $0.remoteKey != nil }.map(\.key)
        return RemoteApplyResult(
            appliedKeys: boxes.keys.sorted { $0.rawValue < $1.rawValue },
            absentKeys: remotelyOverridable.filter { boxes[$0] == nil }
        )
    }

    /// Drops every remote value, so flags fall through to the sources beneath.
    public func clear() {
        lock.lock()
        values = [:]
        lock.unlock()
        subject.send(.all)
    }
}
