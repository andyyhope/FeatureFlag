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

    /// How each supplied value compares to the flag's compiled default.
    ///
    /// One entry per applied flag — the only flags for which both a default and a usable
    /// incoming value exist. Purely informational: whether a value matches its default
    /// or differs from it, ``isComplete`` is unaffected.
    public let defaults: [FlagDefaultComparison]

    /// Applied flags whose config value equals the compiled default — the config is
    /// restating what the app already ships, and could omit them.
    public var matchesDefault: [FlagKey] {
        defaults.filter(\.matchesDefault).map(\.key)
    }

    /// Applied flags whose config value differs from the compiled default — the values
    /// this config actually changes.
    public var changesDefault: [FlagKey] {
        defaults.filter { $0.matchesDefault == false }.map(\.key)
    }

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

        let entriesByKey = Dictionary(
            schema.flags.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        self.defaults =
            applied
            .compactMap { key -> FlagDefaultComparison? in
                guard let incoming = mapping.boxes[key], let entry = entriesByKey[key] else {
                    return nil
                }
                let base = entry.defaultValue
                let records = entry.recordShape.map { shape in
                    FlagRecordDiff.diff(
                        default: base.recordValues(matching: shape) ?? [],
                        incoming: incoming.recordValues(matching: shape) ?? [],
                        shape: shape
                    )
                }
                return FlagDefaultComparison(
                    key: key, defaultValue: base, incomingValue: incoming, records: records
                )
            }
            .sorted { $0.key.rawValue < $1.key.rawValue }
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
                let childPrefix = prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"
                collectLeafPaths(child, prefix: childPrefix, into: &paths)
            }
        default:
            // Not at the root: a payload that is a bare scalar, or empty at the top,
            // has no path to name, and an empty-string "path" fails strict on a blank
            // bullet. A nested empty container still has a real path and stays reported.
            if prefix.isEmpty == false { paths.append(prefix) }
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
    ///   - ignoredPrefixes: Path prefixes whose unconsumed values are allowed even
    ///     under `strict` — the metadata a file is expected to carry.
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

/// How one flag's compiled default compares to the value a config supplies for it.
public struct FlagDefaultComparison: Sendable, Equatable, CustomStringConvertible {

    public let key: FlagKey

    /// The value compiled into the app, from `@Flag(default:)`.
    public let defaultValue: FlagValueBox

    /// The value the config supplied, as a real apply would store it.
    public let incomingValue: FlagValueBox

    /// For a record flag, the per-record breakdown — which records were added, removed,
    /// or changed, and which fields. `nil` for a scalar flag; empty when the records
    /// match. Reading two record lists as one line each is unreadable, so this is how a
    /// record flag's diff is meant to be shown.
    public let records: [FlagRecordDiff]?

    /// Whether the config is restating the compiled default rather than changing it.
    public var matchesDefault: Bool { defaultValue == incomingValue }

    public init(
        key: FlagKey,
        defaultValue: FlagValueBox,
        incomingValue: FlagValueBox,
        records: [FlagRecordDiff]? = nil
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.incomingValue = incomingValue
        self.records = records
    }

    public var description: String {
        if matchesDefault {
            return "\(key): \(incomingValue.shortMessageDescription) — matches the default"
        }
        if let records {
            guard records.isEmpty == false else {
                // A record flag that reaches here differs (it is not a match) yet no
                // record was added, removed, or edited — the only thing left is order.
                // Say that rather than dumping the two JSON strings the breakdown exists
                // to replace.
                return "\(key): records reordered"
            }
            let body =
                records
                .map { diff in
                    diff.line
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "  \($0)" }
                        .joined(separator: "\n")
                }
                .joined(separator: "\n")
            return "\(key):\n\(body)"
        }
        // A scalar: the default becoming the incoming value, which is what applying this
        // config does.
        return "\(key): \(defaultValue.shortMessageDescription) → \(incomingValue.shortMessageDescription)"
    }
}

extension FlagRecordDiff {

    /// One record's change: a single line when added or removed, and the record name
    /// with each changed field on its own line when changed.
    var line: String {
        switch change {
        case .added:
            return "+ \(identifier)"
        case .removed:
            return "- \(identifier)"
        case let .changed(fields):
            // An unset optional field reads as "unset" rather than a blank, so a line
            // like "minimumSpend: unset → 10" says what happened.
            func describe(_ box: FlagValueBox?) -> String {
                box?.diffFieldDescription ?? "unset"
            }
            let fieldLines = fields.map {
                "    \($0.field): \(describe($0.defaultValue)) → \(describe($0.incomingValue))"
            }
            return (["~ \(identifier):"] + fieldLines).joined(separator: "\n")
        }
    }
}

extension FlagMappingAudit {

    /// The default-versus-config diff as a block: what changes, then what is restated.
    public var defaultsDescription: String {
        guard defaults.isEmpty == false else {
            return "This config changes nothing — it supplies no value for any flag."
        }

        let changes = defaults.filter { $0.matchesDefault == false }
        let restated = defaults.filter(\.matchesDefault)

        var lines = ["Default vs config:"]
        if changes.isEmpty {
            lines.append("  every supplied value matches the compiled default.")
        } else {
            lines.append("  changes (\(changes.count)):")
            for change in changes {
                let rendered = change.description.split(separator: "\n", omittingEmptySubsequences: false)
                lines.append("    • \(rendered[0])")
                lines.append(contentsOf: rendered.dropFirst().map { "      \($0)" })
            }
        }
        if restated.isEmpty == false {
            lines.append("  restated (\(restated.count)) — same as the default, could be omitted:")
            lines.append(contentsOf: restated.map { "    • \($0.key)" })
        }
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
