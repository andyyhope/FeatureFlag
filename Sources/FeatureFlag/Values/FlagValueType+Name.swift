import CoreFoundation

extension FlagValueType {

    /// The type's name as it appears in a published schema, e.g. `bool`,
    /// `array<string>`, `dictionary<int>`.
    public var typeName: String {
        switch self {
        case .bool: return "bool"
        case .int: return "int"
        case .double: return "double"
        case .float: return "float"
        case .string: return "string"
        case .data: return "data"
        case .date: return "date"
        case .url: return "url"
        case let .array(element): return "array<\(element.typeName)>"
        case let .dictionary(value): return "dictionary<\(value.typeName)>"
        }
    }

    /// Parses a name produced by ``typeName``.
    public init?(typeName: String) {
        switch typeName {
        case "bool": self = .bool
        case "int": self = .int
        case "double": self = .double
        case "float": self = .float
        case "string": self = .string
        case "data": self = .data
        case "date": self = .date
        case "url": self = .url
        default:
            guard
                let element = Self.nested(in: typeName, after: "array"),
                let type = FlagValueType(typeName: element)
            else {
                guard
                    let value = Self.nested(in: typeName, after: "dictionary"),
                    let type = FlagValueType(typeName: value)
                else { return nil }
                self = .dictionary(type)
                return
            }
            self = .array(type)
        }
    }

    /// The contents of `prefix<...>`, or `nil` if the name is not that shape.
    private static func nested(in typeName: String, after prefix: String) -> String? {
        let opening = prefix + "<"
        guard typeName.hasPrefix(opening), typeName.hasSuffix(">") else { return nil }
        return String(typeName.dropFirst(opening.count).dropLast())
    }
}

/// Whether a serialised value is a boolean rather than a number.
///
/// `UserDefaults`, `JSONSerialization` and `PropertyListSerialization` all represent
/// booleans as CFBoolean, and both CFBoolean and CFNumber bridge to `NSNumber`, so
/// Swift casting alone cannot tell `1` from `true`. CoreFoundation can.
func isBooleanValue(_ object: Any) -> Bool {
    CFGetTypeID(object as CFTypeRef) == CFBooleanGetTypeID()
}
