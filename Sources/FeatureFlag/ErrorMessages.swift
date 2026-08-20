import Foundation

// Every error this framework throws, in words.
//
// Two spellings have to be good, because callers reach for different ones:
// `String(describing:)` is what a `print` or an interpolation produces, and
// `localizedDescription` is what a logger, an alert and most `catch` blocks use.
// Without `LocalizedError` the second is "The operation couldn't be completed.
// (FeatureFlag.RemoteOverrideError error 1.)", which is worse than saying nothing.
//
// Each message says three things where it can: what happened, to which flag, and what
// to do about it. A message that only names a category sends people to read the source.

// MARK: - Remote overrides

extension RemoteOverrideProblem: CustomStringConvertible {

    public var description: String {
        switch kind {
        case .typeMismatch:
            return
                "'\(remoteKey)' → \(key): expected \(expected ?? "another type")"
                + (found.map { ", got \($0)" } ?? "")

        case .unknownCase:
            return
                "'\(remoteKey)' → \(key): \(found ?? "that value") is not one of "
                + (expected ?? "this flag's cases")

        case .unknownKey:
            // DotPathMapper cannot produce this — it only emits keys it read from the
            // schema — so a custom mapper is the only thing that can, and "check your
            // payload" would send people looking in the wrong place entirely.
            return "\(key): no flag has this key, so the mapper that produced it is wrong"
        }
    }
}

extension RemoteOverrideError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case let .malformed(reason):
            return "The remote payload could not be read: \(reason)."

        case let .rejected(problems):
            guard problems.isEmpty == false else {
                return "Nothing was applied, and no problem was recorded."
            }
            let list = problems.map { "  • \($0)" }.joined(separator: "\n")
            return """
                Nothing was applied. \(problems.count) \
                problem\(problems.count == 1 ? "" : "s"):
                \(list)
                A remote payload is all or nothing, so one bad value leaves every other \
                flag reading whatever sits below this source.
                """
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Import

extension FlagImportProblem: CustomStringConvertible {

    public var description: String {
        switch kind {
        case .typeMismatch:
            return
                "\(key): expected \(expected ?? "another type")"
                + (found.map { ", got \($0)" } ?? "")

        case .unknownCase:
            return
                "\(key): \(found ?? "that value") is not one of "
                + (expected ?? "this flag's cases")

        case .unknownKey:
            return
                "\(key): no flag has this key. The document came from a different app, "
                + "or from a build where the flag was named differently"
        }
    }
}

extension FlagImportError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case let .malformed(reason):
            return "The document could not be read: \(reason)."

        case let .unsupportedFormatVersion(version):
            return """
                The document is format version \(version); this build understands \
                \(FlagPayload.currentFormatVersion). Update whichever app is older.
                """

        case let .rejected(problems):
            guard problems.isEmpty == false else {
                return "Nothing was applied, and no problem was recorded."
            }
            let list = problems.map { "  • \($0)" }.joined(separator: "\n")
            return """
                Nothing was applied. \(problems.count) \
                problem\(problems.count == 1 ? "" : "s"):
                \(list)
                Import is all or nothing, so no flag was changed.
                """
        }
    }

    public var errorDescription: String? { description }
}

extension FlagSerializationError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case let .nonFiniteNumber(key):
            return """
                '\(key)' holds an infinity or a NaN, and JSON can represent neither. \
                Use a finite value, or a sentinel the flag's type already has.
                """
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Schema

extension FlagSchemaError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case let .unsupportedFormatVersion(version):
            return """
                The schema is format version \(version); this build understands \
                \(FlagSchema.currentFormatVersion). Update whichever app is older.
                """

        case let .malformed(reason):
            return "The schema could not be read: \(reason)."

        case .notPublished:
            // The most common first-run failure, and the one most often misdiagnosed:
            // people go and check entitlements when the host has simply never been run.
            return """
                No schema has been published. The host app writes one with \
                publishSchema(), so run it at least once — and check both targets \
                declare the same App Group in their entitlements.
                """
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - QR codes

extension FlagQRCodeError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case let .payloadTooLarge(bytes, limit, overrideCount):
            return """
                \(overrideCount) override\(overrideCount == 1 ? "" : "s") need \(bytes) \
                characters and a QR code holds \(limit). Reset a few, or export JSON \
                instead.
                """

        case .unrecognisedFormat:
            return "Not a flag code. A flag code starts with \"FFQR1:\"."

        case .corrupt:
            return """
                The code could not be decompressed, which usually means a partial scan. \
                Try again with the whole code in frame.
                """

        case .imageGenerationFailed:
            return "Core Image could not render the code."
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Signals

extension FlagSignalError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case .notAcknowledged:
            // Deliberately not "the app is not running". That is the usual cause, not
            // the only one, and stating it as fact is a lie the caller then shows
            // someone who then goes looking for the wrong problem.
            return """
                The host did not confirm it handled the signal in time. It may not be \
                running — iOS will not wake a closed app for another app — or it may not \
                be observing this signal's type.
                """

        case let .unavailableAppGroup(identifier):
            return """
                The App Group '\(identifier)' could not be opened. Add it to this \
                target's entitlements, and check it matches the host's exactly.
                """
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Sources

extension FlagError: CustomStringConvertible, LocalizedError {

    public var description: String {
        switch self {
        case .noMutableSource:
            return """
                No source in the stack can be written to. Add a UserDefaultsSource or a \
                SnapshotSource — a pole built only from read-only sources has nowhere to \
                put an override.
                """

        case let .unsupportedValue(key):
            return """
                The source refused the value for '\(key)' because it cannot represent \
                it. Property list storage accepts a narrower set of types than a flag \
                can declare.
                """
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Describing an offending value

/// A value as one short, single-line fragment.
///
/// Each problem is a bullet, so a raw newline in a value puts the rest of it in column
/// zero where it reads as another bullet — or as the sentence that closes the report.
/// Length is capped for the same reason: a message is something to read, not the value
/// itself.
func flagQuoted(_ text: String) -> String {
    let escaped =
        text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")

    guard escaped.count > 40 else { return "\"\(escaped)\"" }
    return "\"\(escaped.prefix(40))…\""
}

extension RemoteValue {

    /// This value in a few characters, for a message that has to fit on one line.
    ///
    /// Strings keep their quotes so `"true"` and `true` are told apart, which is the
    /// single most common mistake a backend makes.
    var shortDescription: String {
        switch self {
        case .null: return "null"
        case let .bool(value): return String(value)
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .string(value): return flagQuoted(value)
        case let .data(value): return "\(value.count) bytes"
        case let .date(value): return flagDateFormatter.string(from: value)
        case let .array(values): return "an array of \(values.count)"
        case let .object(values): return "an object with \(values.count) field(s)"
        }
    }
}

extension FlagValueBox {

    /// This value in a few characters, for a message that has to fit on one line.
    var shortMessageDescription: String {
        switch self {
        case let .string(value): return flagQuoted(value)
        case let .bool(value): return String(value)
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .float(value): return String(value)
        case let .url(value): return flagQuoted(value.absoluteString)
        case let .date(value): return flagDateFormatter.string(from: value)
        case let .data(value): return "\(value.count) bytes"
        case let .array(values): return "an array of \(values.count)"
        case let .dictionary(values): return "an object with \(values.count) field(s)"
        }
    }
}

/// A value straight out of `JSONSerialization` or `PropertyListSerialization`, in a
/// few characters.
func flagShortDescription(of value: Any) -> String {
    if let string = value as? String { return flagQuoted(string) }
    if isBooleanValue(value) { return (value as? Bool).map(String.init) ?? "a boolean" }
    if let array = value as? [Any] { return "an array of \(array.count)" }
    if let object = value as? [String: Any] { return "an object with \(object.count) field(s)" }
    return String(describing: value)
}

extension Array where Element == FlagValueBox {

    /// An enum's cases as a message would list them.
    var caseListDescription: String {
        map { box in
            if case let .string(value) = box { return value }
            return String(describing: box)
        }
        .joined(separator: ", ")
    }
}
