import Foundation

/// A decoded remote payload, independent of whether it arrived as JSON or a property
/// list.
///
/// Mappers work against this rather than against `Any`, so a custom mapper is
/// ordinary, testable Swift.
public enum RemoteValue: Sendable, Equatable {

    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([RemoteValue])
    case object([String: RemoteValue])

    /// Reads a value at a dot path, e.g. `featureToggles.checkout.v2`.
    ///
    /// Numeric components index into arrays, so `experiments.0.enabled` works.
    /// Returns `nil` when the path is not present.
    public func value(atPath path: String) -> RemoteValue? {
        var current = self
        for component in path.split(separator: ".") {
            switch current {
            case let .object(members):
                guard let next = members[String(component)] else { return nil }
                current = next

            case let .array(elements):
                guard let index = Int(component), elements.indices.contains(index) else {
                    return nil
                }
                current = elements[index]

            default:
                return nil
            }
        }
        return current
    }
}

extension RemoteValue {

    /// Builds a tree from a deserialised JSON or property list object.
    init(deserialised object: Any) {
        // Booleans have to be recognised before numbers: both bridge to NSNumber.
        if object is NSNull {
            self = .null
        } else if isBooleanValue(object), let value = object as? Bool {
            self = .bool(value)
        } else if let value = object as? Int {
            self = .int(value)
        } else if let value = object as? Double {
            self = .double(value)
        } else if let value = object as? String {
            self = .string(value)
        } else if let value = object as? Data {
            self = .data(value)
        } else if let value = object as? Date {
            self = .date(value)
        } else if let values = object as? [Any] {
            self = .array(values.map(RemoteValue.init(deserialised:)))
        } else if let values = object as? [String: Any] {
            self = .object(values.mapValues(RemoteValue.init(deserialised:)))
        } else {
            self = .null
        }
    }

    /// Converts to a flag value of the declared type, or `nil` if it does not fit.
    ///
    /// Strict, with one deliberate allowance: JSON has a single number type, so a
    /// whole number satisfies a `Double` or `Float` flag. That widening is exact and
    /// the alternative would reject `1` where a backend meant `1.0`. Nothing else is
    /// coerced — `"true"` is not a boolean, `1` is not a boolean, and `1.5` is not an
    /// integer.
    ///
    /// Dates, data and URLs arrive as strings, which is the only representation JSON
    /// has for them and matches how this framework exports them.
    /// This value as a list of records, or `nil` if it is not one.
    ///
    /// A record flag stores text, so without this a backend sending the natural shape —
    /// a list of objects — would be turned away for not being a string. Every field of
    /// the shape must be present and hold its declared type, and an enum field must
    /// name a case this build has, so a payload that would not survive being read back
    /// is refused now rather than discovered later as a flag that quietly stopped
    /// taking effect.
    ///
    /// A backend that sends the list already serialised as text is understood too, and
    /// is held to exactly the same standard.
    func recordBox(matching shape: [FlagRecordField]) -> FlagValueBox? {
        if case let .string(text) = self {
            guard FlagValueBox.string(text).recordValues(matching: shape) != nil else {
                return nil
            }
            return .string(text)
        }

        guard case let .array(values) = self else { return nil }

        var records = [[String: FlagValueBox]]()
        records.reserveCapacity(values.count)

        for value in values {
            guard case let .object(fields) = value else { return nil }

            var boxes = [String: FlagValueBox](minimumCapacity: shape.count)
            for field in shape {
                // Read by the custom key when the field has one: a backend's key can
                // differ from the property name, though the stored form will not.
                guard let raw = fields[field.payloadName], raw != .null else {
                    // Absent or null. An optional field takes nil and is left out of
                    // the stored form. A required field falls back to its declared
                    // default — the same answer a record predating a newly added field
                    // gets — or the record cannot be read.
                    if field.isOptional { continue }
                    guard let fallback = field.defaultValue else { return nil }
                    boxes[field.name] = fallback
                    continue
                }
                // A field holding its own list of records is a string like any other
                // record list, so it recurses rather than being read as one. Without
                // this a backend would have to send a string containing JSON, nested
                // inside JSON, which nothing produces on purpose.
                let converted =
                    field.fields.map { raw.recordBox(matching: $0) }
                    ?? raw.box(as: field.type)

                guard let box = converted else { return nil }

                if let cases = field.cases, cases.contains(box) == false { return nil }
                // Stored under the property name, not the custom key: decoding is the
                // only place the custom key applies.
                boxes[field.name] = box
            }
            records.append(boxes)
        }

        // The same rule the store applies, for the same reason: a list nobody can read
        // should be refused where it arrives rather than discovered later as a flag
        // that quietly stopped taking effect.
        guard FlagValueBox.duplicateKey(in: records, matching: shape) == nil else {
            return nil
        }

        return .records(records)
    }

    /// The duplicate key in this payload, when that is what makes it unusable.
    func duplicateRecordKey(matching shape: [FlagRecordField]) -> FlagValueBox? {
        if case let .string(text) = self {
            return FlagValueBox.string(text).duplicateRecordKey(matching: shape)
        }
        guard case let .array(values) = self else { return nil }

        var records = [[String: FlagValueBox]]()
        for value in values {
            guard case let .object(fields) = value else { return nil }
            var boxes = [String: FlagValueBox]()
            for field in shape {
                guard let raw = fields[field.payloadName], let box = raw.box(as: field.type)
                else { continue }
                boxes[field.name] = box
            }
            records.append(boxes)
        }
        return FlagValueBox.duplicateKey(in: records, matching: shape)
    }

    func box(as type: FlagValueType) -> FlagValueBox? {
        switch (self, type) {
        case let (.bool(value), .bool):
            return .bool(value)

        case let (.int(value), .int):
            return .int(value)

        case let (.int(value), .double):
            return .double(Double(value))

        case let (.int(value), .float):
            return .float(Float(value))

        case let (.double(value), .double):
            return .double(value)

        case let (.double(value), .float):
            return .float(Float(value))

        case let (.string(value), .string):
            return .string(value)

        case let (.string(value), .data):
            return Data(base64Encoded: value).map(FlagValueBox.data)

        case let (.string(value), .date):
            return flagDateFormatter.date(from: value).map(FlagValueBox.date)

        case let (.string(value), .url):
            return URL(string: value).map(FlagValueBox.url)

        case let (.data(value), .data):
            return .data(value)

        case let (.date(value), .date):
            return .date(value)

        case let (.array(values), .array(element)):
            var boxes = [FlagValueBox]()
            boxes.reserveCapacity(values.count)
            for value in values {
                guard let box = value.box(as: element) else { return nil }
                boxes.append(box)
            }
            return .array(boxes)

        case let (.object(values), .dictionary(valueType)):
            var boxes = [String: FlagValueBox](minimumCapacity: values.count)
            for (key, value) in values {
                guard let box = value.box(as: valueType) else { return nil }
                boxes[key] = box
            }
            return .dictionary(boxes)

        default:
            return nil
        }
    }
}
