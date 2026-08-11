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
    }

    public let key: FlagKey
    public let kind: Kind

    public init(key: FlagKey, kind: Kind) {
        self.key = key
        self.kind = kind
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
                options: [.prettyPrinted, .sortedKeys]
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
    /// Unknown keys and mistyped values are both reported, and nothing is applied
    /// unless everything checks out.
    public static func decode(
        _ data: Data,
        as format: FlagPayloadFormat,
        valueTypes: [FlagKey: FlagValueType]
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
                problems.append(FlagImportProblem(key: key, kind: .unknownKey))
                continue
            }

            let box: FlagValueBox? =
                switch format {
                case .json: FlagValueBox(jsonValue: rawValue, as: type)
                case .plist: FlagValueBox(propertyListValue: rawValue, as: type)
                }

            guard let box else {
                problems.append(FlagImportProblem(key: key, kind: .typeMismatch))
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
