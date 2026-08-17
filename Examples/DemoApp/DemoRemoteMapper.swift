import FeatureFlag

/// Reads both shapes this app's backend has ever sent.
///
/// The built-in ``DotPathMapper`` handles the ordinary one, where every flag lives at a
/// path: `featureToggles.onboarding.v2`. It cannot handle the other, where the flags
/// arrive as a list and the flag's name is a *field* rather than a key — no path
/// addresses "the record whose flag is new-onboarding".
///
/// ```json
/// { "experiments": [ { "flag": "new-onboarding", "enabled": true } ] }
/// ```
///
/// That is what a custom mapper is for, and why it takes the decoded tree rather than
/// bytes: reshaping a payload is ordinary, testable Swift. Values come back raw —
/// checking them against each flag's declared type is the source's job, so a mapper
/// never thinks about boxing.
struct DemoRemoteMapper: RemoteOverrideMapper {

    /// Composed rather than reimplemented: the old shape still works exactly as it did.
    private let paths = DotPathMapper()

    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        guard case let .array(records)? = value.value(atPath: "experiments") else {
            return try paths.map(value, schema: schema)
        }

        var result = [FlagKey: RemoteValue]()
        for record in records {
            guard
                case let .string(name)? = record.value(atPath: "flag"),
                case let .bool(enabled)? = record.value(atPath: "enabled")
            else { continue }

            // Named by the key the schema publishes, so a typo here reaches the source
            // as a key no flag has — reported as .unknownKey rather than silently doing
            // nothing, which would look exactly like a backend that sent no overrides.
            result[FlagKey(name)] = .bool(enabled)
        }
        return result
    }
}
