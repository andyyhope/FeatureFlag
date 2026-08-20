import Foundation

/// A set of flag overrides, ready to be written to a file, shared, or carried in a QR
/// code.
///
/// Only overridden flags travel. Exporting every flag would mostly be a copy of the
/// defaults already compiled into the app, and would not fit in a QR code.
public struct FlagPayload: Sendable, Equatable {

    /// Bumped when the document's shape changes incompatibly.
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let values: [FlagKey: FlagValueBox]

    public init(
        values: [FlagKey: FlagValueBox],
        exportedAt: Date = Date(),
        formatVersion: Int = FlagPayload.currentFormatVersion
    ) {
        self.values = values
        self.exportedAt = exportedAt
        self.formatVersion = formatVersion
    }
}

public enum FlagPayloadFormat: Sendable, Hashable {
    case json
    case plist
}

/// Something wrong with one key in an incoming payload.
public struct FlagImportProblem: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        /// No flag in this app has that key.
        case unknownKey
        /// The value is not of the flag's declared type.
        case typeMismatch
        /// The value is not one of the enum's cases.
        ///
        /// A document written by a build with more cases than this one would otherwise
        /// store a value every read falls back from — invisible in an editor, and
        /// indistinguishable from a flag that simply does not work.
        case unknownCase
    }

    public let key: FlagKey
    public let kind: Kind

    /// What the flag would have accepted — a type name, or an enum's cases. Present
    /// for the message; ``kind`` is what to switch on.
    public let expected: String?

    /// What the document actually held, short enough to read in one line.
    public let found: String?

    public init(key: FlagKey, kind: Kind, expected: String? = nil, found: String? = nil) {
        self.key = key
        self.kind = kind
        self.expected = expected
        self.found = found
    }
}

public enum FlagImportError: Error, Equatable {
    case malformed(String)
    case unsupportedFormatVersion(Int)

    /// Every problem found, and nothing applied. Import is all-or-nothing so an app
    /// never runs on half a configuration.
    case rejected([FlagImportProblem])
}

public struct FlagImportResult: Sendable, Equatable {
    public let appliedKeys: [FlagKey]
}

// MARK: - Serialisation

/// Something that cannot be written out.
public enum FlagSerializationError: Error, Equatable {

    /// A flag holds an infinity or a NaN, which JSON cannot represent.
    ///
    /// Handing one to `JSONSerialization` raises an Objective-C exception that Swift
    /// cannot catch, so the process would die. This is thrown first instead.
    case nonFiniteNumber(FlagKey)
}

extension FlagPayload {

    public func encoded(as format: FlagPayloadFormat) throws -> Data {
        switch format {
        case .json:
            if let key = values.first(where: { $0.value.containsNonFiniteNumber })?.key {
                throw FlagSerializationError.nonFiniteNumber(key)
            }
            return try JSONSerialization.data(
                withJSONObject: object(using: \.jsonValue),
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        case .plist:
            return try PropertyListSerialization.data(
                fromPropertyList: object(using: \.propertyListValue),
                format: .xml,
                options: 0
            )
        }
    }

    private func object(using representation: (FlagValueBox) -> Any) -> [String: Any] {
        [
            "formatVersion": formatVersion,
            "exportedAt": flagDateFormatter.string(from: exportedAt),
            "values": Dictionary(
                uniqueKeysWithValues: values.map { ($0.key.rawValue, representation($0.value)) }
            ),
        ]
    }

    /// Reads a payload, validating every value against the types the app declares.
    ///
    /// Unknown keys, mistyped values and — where `cases` is supplied — enum cases this
    /// build does not have are all reported, and nothing is applied unless everything
    /// checks out.
    ///
    /// - Parameters:
    ///   - data: The document, as exported.
    ///   - format: How to parse it. A JSON document read as a property list, or the
    ///     reverse, is rejected rather than guessed at.
    ///   - valueTypes: The declared type of each flag, as ``FlagSchema/valueTypes``
    ///     provides them. A key absent from this is an unknown flag.
    ///   - cases: The permitted values for each enum flag, as ``FlagSchema/valueCases``
    ///     provides them. Omitting it skips that check, which only makes sense when the
    ///     caller has no schema to check against.
    ///   - recordShapes: The fields of each record flag, as ``FlagSchema/recordShapes``
    ///     provides them. Omitting it means a record flag is checked only for being a
    ///     string, which any text satisfies.
    public static func decode(
        _ data: Data,
        as format: FlagPayloadFormat,
        valueTypes: [FlagKey: FlagValueType],
        cases: [FlagKey: [FlagValueBox]] = [:],
        recordShapes: [FlagKey: [FlagRecordField]] = [:]
    ) throws -> FlagPayload {
        let object: [String: Any]
        switch format {
        case .json:
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw FlagImportError.malformed("not a JSON object") }
            object = parsed
        case .plist:
            guard
                let parsed = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any]
            else { throw FlagImportError.malformed("not a property list dictionary") }
            object = parsed
        }

        guard let version = object["formatVersion"] as? Int else {
            throw FlagImportError.malformed("missing formatVersion")
        }
        guard version == currentFormatVersion else {
            throw FlagImportError.unsupportedFormatVersion(version)
        }
        guard let rawValues = object["values"] as? [String: Any] else {
            throw FlagImportError.malformed("missing values")
        }

        var values = [FlagKey: FlagValueBox]()
        var problems = [FlagImportProblem]()

        for (rawKey, rawValue) in rawValues {
            let key = FlagKey(rawKey)
            guard let type = valueTypes[key] else {
                problems.append(
                    FlagImportProblem(
                        key: key, kind: .unknownKey, found: flagShortDescription(of: rawValue)
                    )
                )
                continue
            }

            let box: FlagValueBox? =
                switch format {
                case .json: FlagValueBox(jsonValue: rawValue, as: type)
                case .plist: FlagValueBox(propertyListValue: rawValue, as: type)
                }

            guard let box else {
                problems.append(
                    FlagImportProblem(
                        key: key,
                        kind: .typeMismatch,
                        expected: type.typeName,
                        found: flagShortDescription(of: rawValue)
                    )
                )
                continue
            }

            // Enums declare their cases, so a document from a build that has more of
            // them is caught here rather than at every read, the same way a remote
            // payload is.
            if let permitted = cases[key], permitted.isEmpty == false, !permitted.contains(box) {
                problems.append(
                    FlagImportProblem(
                        key: key,
                        kind: .unknownCase,
                        expected: permitted.caseListDescription,
                        found: flagShortDescription(of: rawValue)
                    )
                )
                continue
            }

            // A record list is a string, which any text satisfies — so being the right
            // type is not enough to know the app can read it. Checked here rather than
            // left to the read, where it would fall back to the default and look like
            // an import that did nothing.
            if let shape = recordShapes[key], box.recordValues(matching: shape) == nil {
                problems.append(
                    FlagImportProblem(
                        key: key,
                        kind: .typeMismatch,
                        expected: box.duplicateRecordKey(matching: shape) == nil
                            ? "a list of records (\(shape.map(\.name).joined(separator: ", ")))"
                            : "every record to have its own \(shape.first(where: \.isKey)?.name ?? "key")",
                        found: box.duplicateRecordKey(matching: shape)
                            .map { "two with \($0.shortMessageDescription)" }
                            ?? flagShortDescription(of: rawValue)
                    )
                )
                continue
            }

            values[key] = box
        }

        guard problems.isEmpty else {
            throw FlagImportError.rejected(problems.sorted { $0.key.rawValue < $1.key.rawValue })
        }

        return FlagPayload(
            values: values,
            exportedAt: (object["exportedAt"] as? String).flatMap(flagDateFormatter.date(from:))
                ?? Date(timeIntervalSince1970: 0),
            formatVersion: version
        )
    }
}
