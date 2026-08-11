import Foundation

/// Second-precision internet date time, shared by every JSON representation here so
/// exported documents and published schemas agree.
let flagDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

extension FlagValueBox {

    /// The JSON representation of this value.
    ///
    /// JSON has no date, data or URL, and the schema already records each flag's type,
    /// so these become plain strings rather than `{"$type": ...}` wrappers. Exported
    /// documents stay something a person can read and edit by hand.
    ///
    /// Dates carry second precision. Anything finer is not meaningful for a feature
    /// flag and would only make the output harder to read.
    public var jsonValue: Any {
        switch self {
        case let .bool(value): return value
        case let .int(value): return value
        case let .double(value): return value
        case let .float(value): return Double(value)
        case let .string(value): return value
        case let .data(value): return value.base64EncodedString()
        case let .date(value): return flagDateFormatter.string(from: value)
        case let .url(value): return value.absoluteString
        case let .array(boxes): return boxes.map(\.jsonValue)
        case let .dictionary(boxes): return boxes.mapValues(\.jsonValue)
        }
    }

    /// Rebuilds a box from JSON, guided by the flag's declared type.
    ///
    /// Returns `nil` when the value cannot be read as that type, which is what makes
    /// import strict.
    public init?(jsonValue object: Any, as type: FlagValueType) {
        switch type {
        // JSON booleans and numbers are both NSNumber once parsed, so `true` and `1`
        // need telling apart the same way they do in a property list.
        case .bool:
            guard isBooleanValue(object), let value = object as? Bool else { return nil }
            self = .bool(value)

        case .int:
            guard !isBooleanValue(object), let value = object as? Int else { return nil }
            self = .int(value)

        case .double:
            guard !isBooleanValue(object), let value = object as? Double else { return nil }
            self = .double(value)

        case .float:
            guard !isBooleanValue(object), let value = object as? Double else { return nil }
            self = .float(Float(value))

        case .string:
            guard let value = object as? String else { return nil }
            self = .string(value)

        case .data:
            guard let value = object as? String, let data = Data(base64Encoded: value) else {
                return nil
            }
            self = .data(data)

        case .date:
            guard let value = object as? String, let date = flagDateFormatter.date(from: value)
            else { return nil }
            self = .date(date)

        case .url:
            guard let value = object as? String, let url = URL(string: value) else { return nil }
            self = .url(url)

        case let .array(element):
            guard let values = object as? [Any] else { return nil }
            var boxes = [FlagValueBox]()
            boxes.reserveCapacity(values.count)
            for value in values {
                guard let box = FlagValueBox(jsonValue: value, as: element) else { return nil }
                boxes.append(box)
            }
            self = .array(boxes)

        case let .dictionary(valueType):
            guard let values = object as? [String: Any] else { return nil }
            var boxes = [String: FlagValueBox](minimumCapacity: values.count)
            for (key, value) in values {
                guard let box = FlagValueBox(jsonValue: value, as: valueType) else { return nil }
                boxes[key] = box
            }
            self = .dictionary(boxes)
        }
    }
}
