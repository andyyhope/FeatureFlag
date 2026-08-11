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
