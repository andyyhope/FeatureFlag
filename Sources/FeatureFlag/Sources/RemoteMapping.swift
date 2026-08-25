import Foundation

/// The result of turning a decoded payload into flag values, before anything is stored.
///
/// One codepath, so what a ``FlagMappingAudit`` reports and what
/// ``RemoteOverrideSource/apply(_:)`` does can never disagree: the audit describes this,
/// and apply stores it or throws on its problems.
struct RemoteMapping {

    /// Flags whose remote value mapped cleanly to their declared type.
    var boxes: [FlagKey: FlagValueBox]

    /// Everything wrong: a value of the wrong type, an enum case this build lacks, or a
    /// key no flag has. Empty for a payload that would apply.
    var problems: [RemoteOverrideProblem]
}

extension FlagSchema {

    /// Runs the mapper and validates every value it produced, without applying anything.
    ///
    /// Deliberately collects every problem rather than stopping at the first: a large
    /// payload is worth checking all at once, and ``RemoteOverrideSource`` throws the
    /// whole list anyway.
    func mapRemote(
        _ value: RemoteValue,
        using mapper: any RemoteOverrideMapper
    ) throws -> RemoteMapping {
        let mapped = try mapper.map(value, schema: self)

        // First wins on a duplicated key rather than trapping — a schema handed in
        // directly is not guaranteed well formed the way one built from a container is.
        let entries = Dictionary(
            flags.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )

        var boxes = [FlagKey: FlagValueBox]()
        var problems = [RemoteOverrideProblem]()

        for (key, remoteValue) in mapped {
            guard let entry = entries[key] else {
                problems.append(
                    RemoteOverrideProblem(
                        key: key,
                        remoteKey: key.rawValue,
                        kind: .unknownKey,
                        found: remoteValue.shortDescription
                    )
                )
                continue
            }

            // A record flag stores text, so it cannot be checked by type alone: the
            // shape published beside it is what says whether the list a backend sent is
            // one this build can read. A bad field inside a record is reported as a
            // mismatch on the flag, since a problem names a flag and not a field.
            let converted =
                entry.recordShape.map { remoteValue.recordBox(matching: $0) }
                ?? remoteValue.box(as: entry.valueType)

            guard let box = converted else {
                problems.append(
                    RemoteOverrideProblem(
                        key: key,
                        remoteKey: entry.remoteKey ?? key.rawValue,
                        kind: .typeMismatch,
                        expected: entry.expectedDescription(for: remoteValue),
                        found: entry.foundDescription(for: remoteValue)
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
                        kind: .unknownCase,
                        expected: cases.caseListDescription,
                        found: remoteValue.shortDescription
                    )
                )
                continue
            }

            boxes[key] = box
        }

        return RemoteMapping(boxes: boxes, problems: problems)
    }
}
