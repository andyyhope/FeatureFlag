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

    /// What the field falls back to when a stored record does not carry it, taken from
    /// the initialiser it was written with.
    ///
    /// This is what makes adding a field to a record survivable: a list written before
    /// the field existed is filled rather than rejected. A field with no initialiser
    /// has no default, and a record missing it is still refused — there would be
    /// nothing honest to put there.
    public let defaultValue: FlagValueBox?

    /// Whether this field is the record's key — the thing that tells one record from
    /// another. At most one field in a shape carries it.
    public let isKey: Bool

    /// The fields of each record, when this field is itself a ``FlagRecords`` list.
    ///
    /// A nested list is a string like any other record list, so without this an editor
    /// would show a block of escaped JSON and a backend would have to send one.
    public let fields: [FlagRecordField]?

    public init(
        name: String,
        type: FlagValueType,
        cases: [FlagValueBox]? = nil,
        defaultValue: FlagValueBox? = nil,
        fields: [FlagRecordField]? = nil,
        isKey: Bool = false
    ) {
        self.name = name
        self.type = type
        self.cases = cases
        self.defaultValue = defaultValue
        self.fields = fields
        self.isKey = isKey
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

    /// The field that tells one record from another, if the record names one.
    static var flagRecordKey: String? { get }

    /// Each field's value, keyed by field name.
    var flagRecordBoxes: [String: FlagValueBox] { get }

    /// Rebuilds a record, or fails if a field is missing or holds the wrong type.
    init?(flagRecordBoxes: [String: FlagValueBox])
}

extension FlagRecord {

    /// Records are told apart by position unless they say otherwise.
    public static var flagRecordKey: String? { nil }
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

    /// The record with this key, or `nil` when none has it — or when the record names
    /// no key, since then there is nothing to look one up by.
    public subscript(key: some FlagValue) -> Record? {
        guard let name = Record.flagRecordKey else { return nil }
        let wanted = key.box
        return values.first { $0.flagRecordBoxes[name] == wanted }
    }

    public var box: FlagValueBox {
        .records(values.map(\.flagRecordBoxes))
    }

    public init?(box: FlagValueBox) {
        guard let records = box.recordValues(matching: Record.flagRecordShape) else {
            return nil
        }

        var values = [Record]()
        values.reserveCapacity(records.count)
        for boxes in records {
            guard let record = Record(flagRecordBoxes: boxes) else { return nil }
            values.append(record)
        }

        self.values = values
    }
}

// MARK: - Reading records without their Swift type

extension FlagValueBox {

    /// The records inside a record flag's stored text, read through a shape alone.
    ///
    /// This is what a companion app has to work with: it holds the schema and never the
    /// host's Swift types, so a shape is the only description of a record it will ever
    /// see. ``FlagRecords`` decodes through here too, so the two cannot drift.
    ///
    /// Every field of the shape must be present and hold its declared type. Returning a
    /// partial list would mean an editor showing a value the host had already rejected.
    public func recordValues(matching shape: [FlagRecordField]) -> [[String: FlagValueBox]]? {
        guard let records = parsedRecords(matching: shape) else { return nil }
        // Two records sharing a key is a mistake with no correct behaviour: picking one
        // would leave the app running on a value nobody chose, and picking neither is
        // what the caller already does with anything else it cannot read.
        guard Self.duplicateKey(in: records, matching: shape) == nil else { return nil }
        return records
    }

    /// The duplicate key in this value, when that is what makes it unreadable.
    ///
    /// Only for saying so: the rejection has already happened by the time anyone asks.
    public func duplicateRecordKey(matching shape: [FlagRecordField]) -> FlagValueBox? {
        guard let records = parsedRecords(matching: shape) else { return nil }
        return Self.duplicateKey(in: records, matching: shape)
    }

    /// The records this value holds, before the uniqueness rule is applied.
    private func parsedRecords(matching shape: [FlagRecordField]) -> [[String: FlagValueBox]]? {
        guard
            case let .string(json) = self,
            let objects = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [[String: Any]]
        else { return nil }

        var records = [[String: FlagValueBox]]()
        records.reserveCapacity(objects.count)

        for object in objects {
            var boxes = [String: FlagValueBox](minimumCapacity: shape.count)
            for field in shape {
                // Absent is a migration — a record written before the field existed —
                // and its declared default is the honest thing to put there. Present
                // but wrong is not: overwriting it would be guessing, and would hide a
                // stored value that genuinely disagrees with this build.
                guard let value = object[field.name] else {
                    guard let fallback = field.defaultValue else { return nil }
                    boxes[field.name] = fallback
                    continue
                }
                guard let box = FlagValueBox(jsonValue: value, as: field.type) else {
                    return nil
                }
                boxes[field.name] = box
            }
            records.append(boxes)
        }

        return records
    }

    /// The first key claimed by more than one record, or `nil` when every one is
    /// distinct — and when the shape names no key, since then there is nothing to share.
    public static func duplicateKey(
        in records: [[String: FlagValueBox]],
        matching shape: [FlagRecordField]
    ) -> FlagValueBox? {
        guard let key = shape.first(where: \.isKey)?.name else { return nil }

        var seen = Set<String>()
        for record in records {
            guard let value = record[key] else { continue }
            // Compared as it will be stored, not as it is held. A Date carries more
            // precision in memory than the wire format keeps, so two records made a
            // moment apart looked distinct here and identical once written — a list
            // this check passed and the reader then refused.
            if seen.insert(value.storageIdentity).inserted == false { return value }
        }
        return nil
    }

    /// A list of records as the text a record flag stores.
    ///
    /// The other half of ``recordValues(matching:)``, for an editor that has changed
    /// something and needs to write it back the way the host will read it.
    public static func records(_ records: [[String: FlagValueBox]]) -> FlagValueBox {
        // An infinity or a NaN makes JSONSerialization raise an Objective-C exception,
        // which no `try` can catch — the process dies with a message about JSON writing
        // and nothing about which flag caused it. Everywhere else that serialises checks
        // first and throws something catchable; boxing cannot throw, so this traps
        // instead, naming the field.
        precondition(
            nonFiniteRecordField(in: records) == nil,
            """
            The record field '\(nonFiniteRecordField(in: records) ?? "")' holds an \
            infinity or a NaN, and a list of records is stored as JSON, which can \
            represent neither. Use a finite value, or a sentinel the field's type \
            already has.
            """
        )

        let objects = records.map { $0.mapValues(\.jsonValue) }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: objects,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else { return .string("[]") }
        return .string(String(decoding: data, as: UTF8.self))
    }
}

extension FlagValueBox {

    /// The first field holding a number JSON cannot write, or `nil` when every one of
    /// them can be written.
    static func nonFiniteRecordField(in records: [[String: FlagValueBox]]) -> String? {
        for record in records {
            // Sorted so the field named is the same one every time, rather than
            // whichever the dictionary happened to yield first.
            for name in record.keys.sorted() where record[name]?.containsNonFiniteNumber == true {
                return name
            }
        }
        return nil
    }
}

extension FlagValueBox {

    /// This value as its stored form identifies it.
    ///
    /// Two values are the same key when they are written the same way, which is not
    /// always the same as being equal in memory: a `Date` carries more precision than
    /// the wire format keeps. Anything deciding whether a key is taken has to ask this
    /// rather than compare boxes, or it will disagree with the reader.
    public var storageIdentity: String {
        String(describing: jsonValue)
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
