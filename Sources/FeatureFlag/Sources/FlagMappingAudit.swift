import Foundation

/// A check that a remote payload wires up the flags it should — run without an app.
///
/// The problem it solves is a large config file: too many values to trace by hand, and
/// two ways for one to be wrong that no single assertion catches. A flag whose
/// `remoteKey` matches nothing is not an error — it simply falls through to its default,
/// which looks exactly like a backend that sent nothing. And a value in the file that no
/// flag reads is invisible until someone notices the feature never turned on.
///
/// ```swift
/// let audit = try FlagMappingAudit(AppFlags.self, applying: json)
/// XCTAssertTrue(audit.isComplete, "\(audit)")
/// ```
///
/// It reuses the same validation ``RemoteOverrideSource`` applies, so a value it reports
/// as mapped is one a real apply would accept. Types are therefore never the audit's
/// concern — only coverage, in both directions.
public struct FlagMappingAudit: Sendable, Equatable, CustomStringConvertible {

    /// Flags whose `remoteKey` found a value that fits their declared type.
    public let applied: [FlagKey]

    /// Flags with a `remoteKey` the payload did not supply. The most common cause is a
    /// typo in the key, which is otherwise indistinguishable from an absent value.
    public let absent: [FlagKey]

    /// Values the payload supplied that did not fit — wrong type, or an enum case this
    /// build does not have. The same problems a real apply would reject.
    public let mismatched: [RemoteOverrideProblem]

    /// Paths in the payload that no flag reads.
    ///
    /// Usually not a fault — a real config carries backend metadata, versions, and keys
    /// other apps share the document for — so these do not fail the audit unless you ask
    /// for `strict`. But a value you *expected* a flag to read sitting here is a path
    /// typo seen from the other side.
    ///
    /// Computed from the flags' declared `remoteKey` paths, so it reflects
    /// ``DotPathMapper``. A custom mapper that reads the payload some other way makes
    /// this advisory rather than exact.
    public let unconsumed: [String]

    /// Flags that declare no `remoteKey`, so nothing a payload contains can touch them.
    /// Neither applied nor absent — listed so the audit accounts for every flag.
    public let notRemotelyOverridable: [FlagKey]

    // MARK: - Building

    /// Audits a container against a payload, decoding it the way the source would.
    public init<Root: FlagContainer>(
        _ type: Root.Type = Root.self,
        applying data: Data,
        format: FlagPayloadFormat = .json,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        keyEncoding: KeyEncoding = .kebabcase
    ) throws {
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

        try self.init(
            schema: FlagSchema(Root.self, keyEncoding: keyEncoding),
            applying: RemoteValue(deserialised: object),
            mapper: mapper
        )
    }

    /// Audits a schema against an already-decoded payload.
    public init(
        schema: FlagSchema,
        applying value: RemoteValue,
        mapper: any RemoteOverrideMapper = DotPathMapper()
    ) throws {
        let mapping = try schema.mapRemote(value, using: mapper)

        let boxed = Set(mapping.boxes.keys)
        let mismatchedKeys = Set(mapping.problems.map(\.key))

        var applied = [FlagKey]()
        var absent = [FlagKey]()
        var notRemote = [FlagKey]()
        for entry in schema.flags {
            guard entry.remoteKey != nil else {
                notRemote.append(entry.key)
                continue
            }
            if boxed.contains(entry.key) {
                applied.append(entry.key)
            } else if mismatchedKeys.contains(entry.key) == false {
                // A mismatched flag supplied a value; it is a problem, not an absence.
                absent.append(entry.key)
            }
        }

        self.applied = applied.sorted { $0.rawValue < $1.rawValue }
        self.absent = absent.sorted { $0.rawValue < $1.rawValue }
        self.mismatched = mapping.problems.sorted { $0.key.rawValue < $1.key.rawValue }
        self.notRemotelyOverridable = notRemote.sorted { $0.rawValue < $1.rawValue }
        self.unconsumed = Self.unconsumedPaths(
            in: value, claimedBy: schema.flags.compactMap(\.remoteKey)
        )
    }

    // MARK: - Reverse coverage

    /// Every scalar path in the payload that no `remoteKey` claims.
    ///
    /// A path is claimed when a `remoteKey` equals it or is one of its ancestors — a
    /// record flag's key names a subtree, and everything beneath it is read as part of
    /// that one value.
    private static func unconsumedPaths(
        in value: RemoteValue,
        claimedBy remoteKeys: [String]
    ) -> [String] {
        let claims = Set(remoteKeys)

        func isClaimed(_ path: String) -> Bool {
            if claims.contains(path) { return true }
            // An ancestor claim: some remoteKey is a strict prefix at a path boundary.
            return claims.contains { path.hasPrefix($0 + ".") }
        }

        var unclaimed = [String]()
        var leaves = [String]()
        Self.collectLeafPaths(value, prefix: "", into: &leaves)
        for path in leaves where isClaimed(path) == false {
            unclaimed.append(path)
        }
        return unclaimed.sorted()
    }

    /// Walks to every scalar, recording its dot path. An empty object or array is a leaf
    /// too — there is a value there, even if it holds nothing.
    private static func collectLeafPaths(
        _ value: RemoteValue,
        prefix: String,
        into paths: inout [String]
    ) {
        switch value {
        case let .object(members) where members.isEmpty == false:
            for (name, child) in members {
                collectLeafPaths(child, prefix: prefix.isEmpty ? name : "\(prefix).\(name)", into: &paths)
            }
        case let .array(elements) where elements.isEmpty == false:
            for (index, child) in elements.enumerated() {
                collectLeafPaths(child, prefix: "\(prefix).\(index)", into: &paths)
            }
        default:
            paths.append(prefix)
        }
    }

    // MARK: - Verdict

    /// Whether the payload wires up every flag it should.
    ///
    /// By default: nothing absent and nothing mismatched. Unconsumed values are reported
    /// but do not fail, since a real config legitimately carries them.
    public var isComplete: Bool { isComplete(strict: false) }

    /// - Parameters:
    ///   - strict: Also require that every value in the payload is read by a flag.
    ///   - ignoring: Path prefixes whose unconsumed values are allowed even under
    ///     `strict` — the metadata a file is expected to carry.
    public func isComplete(strict: Bool, ignoring ignoredPrefixes: [String] = []) -> Bool {
        guard absent.isEmpty, mismatched.isEmpty else { return false }
        guard strict else { return true }
        return unconsumed(ignoring: ignoredPrefixes).isEmpty
    }

    /// The unconsumed paths that remain after dropping anything under an ignored prefix.
    public func unconsumed(ignoring ignoredPrefixes: [String]) -> [String] {
        guard ignoredPrefixes.isEmpty == false else { return unconsumed }
        return unconsumed.filter { path in
            ignoredPrefixes.contains { path == $0 || path.hasPrefix($0 + ".") } == false
        }
    }

    /// Throws a described error when the payload is not complete, for a `try` at the top
    /// of a test or a debug-build assertion. Silent when everything checks out.
    public func requireComplete(strict: Bool = false, ignoring: [String] = []) throws {
        guard isComplete(strict: strict, ignoring: ignoring) == false else { return }
        throw FlagMappingAuditError.incomplete(description(strict: strict, ignoring: ignoring))
    }

    // MARK: - Reporting

    public var description: String { description(strict: false, ignoring: []) }

    /// The full report, tailored to how you are judging completeness — `strict` changes
    /// the headline verdict, and `ignoring` drops the unconsumed paths you have excused.
    public func description(strict: Bool, ignoring: [String]) -> String {
        let shownUnconsumed = unconsumed(ignoring: ignoring)
        let overridable = applied.count + absent.count + mismatched.count

        var lines = [String]()
        if absent.isEmpty, mismatched.isEmpty, (strict == false || shownUnconsumed.isEmpty) {
            lines.append("Flag mapping audit — complete.")
        } else {
            lines.append("Flag mapping audit — incomplete.")
        }

        if absent.isEmpty == false {
            lines.append("  absent (\(absent.count)) — a flag declares this path, the payload has nothing there:")
            lines.append(contentsOf: absent.map { "    • \($0)" })
        }
        if mismatched.isEmpty == false {
            lines.append("  mismatched (\(mismatched.count)):")
            lines.append(contentsOf: mismatched.map { "    • \($0)" })
        }
        if shownUnconsumed.isEmpty == false {
            let note = strict ? "" : " — usually fine, often backend metadata"
            lines.append("  unconsumed (\(shownUnconsumed.count))\(note) — no flag reads these:")
            lines.append(contentsOf: shownUnconsumed.map { "    • \($0)" })
        }
        lines.append("  \(applied.count) of \(overridable) remotely-overridable flags applied.")
        return lines.joined(separator: "\n")
    }
}

/// A payload that did not wire up every flag it should.
public enum FlagMappingAuditError: Error, CustomStringConvertible, LocalizedError {

    case incomplete(String)

    public var description: String {
        switch self {
        case let .incomplete(report): return report
        }
    }

    public var errorDescription: String? { description }
}
