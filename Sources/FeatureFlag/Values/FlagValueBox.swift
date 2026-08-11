import Foundation

/// The canonical boxed representation of a flag value.
///
/// Every storage and transport mechanism in FeatureFlag — `UserDefaults`, JSON, PLIST
/// and QR — reads and writes this one type, so each supported Swift type needs only a
/// single conversion to be usable everywhere.
public enum FlagValueBox: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case float(Float)
    case string(String)
    case data(Data)
    case date(Date)
    case url(URL)
    case array([FlagValueBox])
    case dictionary([String: FlagValueBox])
}

extension FlagValueBox {

    /// Whether this box holds the type a flag declared.
    ///
    /// The resolver skips values that do not match rather than surfacing them, so a
    /// stale or hand-edited store degrades to the next source instead of to a crash.
    /// An empty collection matches any collection of that shape.
    public func matches(_ type: FlagValueType) -> Bool {
        switch (self, type) {
        case (.bool, .bool), (.int, .int), (.double, .double), (.float, .float),
            (.string, .string), (.data, .data), (.date, .date), (.url, .url):
            return true

        case let (.array(boxes), .array(element)):
            return boxes.allSatisfy { $0.matches(element) }

        case let (.dictionary(boxes), .dictionary(value)):
            return boxes.values.allSatisfy { $0.matches(value) }

        default:
            return false
        }
    }
}
