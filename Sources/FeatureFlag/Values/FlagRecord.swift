import Foundation

/// One field of a record, described well enough for an editor that has never seen the
/// type it came from.
public struct FlagRecordField: Hashable, Sendable {

    /// The property name, as written.
    public let name: String

    /// The field's declared type, which is what picks its control.
    public let type: FlagValueType

    /// Every case, when the field is a `CaseIterable` enum. Editors show a picker
    /// rather than a free-text field. `nil` — not empty — when there are none.
    public let cases: [FlagValueBox]?

    public init(name: String, type: FlagValueType, cases: [FlagValueBox]? = nil) {
        self.name = name
        self.type = type
        self.cases = cases
    }
}

/// A fixed shape a flag can hold a list of.
///
/// ```swift
/// @FlagRecord
/// struct Endpoint {
///     var name: String
///     var url: URL
///     var enabled: Bool
/// }
///
/// @Flag(default: [Endpoint(name: "prod", url: …, enabled: true)], description: "Endpoints")
/// var endpoints: FlagRecords<Endpoint>
/// ```
///
/// Conform by hand only if you cannot use the macro. Every field must itself be a
/// ``FlagValue``, which is what lets a record be boxed field by field rather than run
/// through `Codable` — a `Date` inside a record is then written exactly the way a
/// `Date` flag beside it is written.
public protocol FlagRecord: Equatable, Sendable {

    /// The fields, in the order they should be shown.
    static var flagRecordShape: [FlagRecordField] { get }

    /// Each field's value, keyed by field name.
    var flagRecordBoxes: [String: FlagValueBox] { get }

    /// Rebuilds a record, or fails if a field is missing or holds the wrong type.
    init?(flagRecordBoxes: [String: FlagValueBox])
}

/// A list of records, stored as JSON text.
///
/// The list is a `String` as far as storage, transport and validation are concerned,
/// so it travels through `UserDefaults`, JSON, property lists, QR codes and
/// import/export without any of them needing to know what a record is. The shape
/// rides along in the schema, which is what lets a companion app render an editor for
/// it — and lets one that predates records fall back to showing the JSON rather than
/// failing to read the document at all.
public struct FlagRecords<Record: FlagRecord>: FlagValue, ExpressibleByArrayLiteral {

    public var values: [Record]

    public init(_ values: [Record] = []) {
        self.values = values
    }

    public init(arrayLiteral elements: Record...) {
        self.values = elements
    }

    public static var flagValueType: FlagValueType { .string }

    public var box: FlagValueBox {
        let objects = values.map { $0.flagRecordBoxes.mapValues(\.jsonValue) }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: objects,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else { return .string("[]") }
        return .string(String(decoding: data, as: UTF8.self))
    }

    public init?(box: FlagValueBox) {
        guard
            case let .string(json) = box,
            let objects = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [[String: Any]]
        else { return nil }

        var values = [Record]()
        values.reserveCapacity(objects.count)

        for object in objects {
            var boxes = [String: FlagValueBox](minimumCapacity: Record.flagRecordShape.count)
            for field in Record.flagRecordShape {
                // A field that is absent or holds the wrong type is left out rather
                // than guessed at, and the record itself decides whether it can do
                // without it. One bad record fails the whole list, as one bad element
                // fails an array — a half-built list is worse than the default.
                guard
                    let value = object[field.name],
                    let box = FlagValueBox(jsonValue: value, as: field.type)
                else { continue }
                boxes[field.name] = box
            }
            guard let record = Record(flagRecordBoxes: boxes) else { return nil }
            values.append(record)
        }

        self.values = values
    }
}

/// Lets the schema layer reach a record list's shape through an existential.
///
/// The same shape as ``FlagValueCases``, and for the same reason: generated code only
/// ever holds a metatype, so this deliberately avoids generics.
public protocol FlagRecordCarrying {
    static var flagRecordShape: [FlagRecordField] { get }
}

extension FlagRecords: FlagRecordCarrying {
    public static var flagRecordShape: [FlagRecordField] { Record.flagRecordShape }
}

/// Describes a flag's record shape, or returns `nil` when it holds no records.
///
/// Generated code calls this for every flag. As with ``_flagValueCases(of:)``, the
/// generic signature is load-bearing: it hides a cast that would otherwise warn
/// "always succeeds" in any container declaring a record flag.
public func _flagRecordShape<Value: FlagValue>(of type: Value.Type) -> [FlagRecordField]? {
    (type as? any FlagRecordCarrying.Type)?.flagRecordShape
}
