import FeatureFlag
import Foundation

/// Which control the editor should show for a flag.
public enum FlagEditorKind: Hashable, Sendable {
    case toggle
    case integer
    case decimal
    case text
    /// A choice between an enum's cases.
    case picker([FlagValueBox])
    case date
    case url
    /// Base64, because there is nothing better to show for arbitrary bytes.
    case data
    /// Collections, edited as JSON text.
    case json
}

extension FlagSchema.Entry {

    /// The control this flag should be edited with.
    ///
    /// A `CaseIterable` enum publishes its cases, which is what turns a free-text
    /// field into a picker — the single biggest difference in whether the companion
    /// app feels finished.
    public var editorKind: FlagEditorKind {
        if let cases, cases.isEmpty == false {
            return .picker(cases)
        }
        switch valueType {
        case .bool: return .toggle
        case .int: return .integer
        case .double, .float: return .decimal
        case .string: return .text
        case .date: return .date
        case .url: return .url
        case .data: return .data
        case .array, .dictionary: return .json
        }
    }
}

extension FlagValueBox {

    /// The value as editable text.
    public var displayString: String {
        switch self {
        case let .bool(value): return value ? "true" : "false"
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .float(value): return String(value)
        case let .string(value): return value
        case let .data(value): return value.base64EncodedString()
        case .date, .url: return jsonValue as? String ?? ""
        case .array, .dictionary:
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: jsonValue,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
            else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Parses edited text according to the flag's declared type.
    ///
    /// Returns `nil` rather than guessing, so the editor can refuse the edit and keep
    /// what was there.
    public init?(displayString string: String, as type: FlagValueType) {
        switch type {
        case .bool:
            switch string.lowercased() {
            case "true", "yes", "1": self = .bool(true)
            case "false", "no", "0": self = .bool(false)
            default: return nil
            }

        case .int:
            guard let value = Int(string) else { return nil }
            self = .int(value)

        case .double:
            guard let value = Double(string) else { return nil }
            self = .double(value)

        case .float:
            guard let value = Float(string) else { return nil }
            self = .float(value)

        case .string:
            self = .string(string)

        case .data:
            guard let value = Data(base64Encoded: string) else { return nil }
            self = .data(value)

        case .date, .url, .array, .dictionary:
            guard let box = Self.parseStructured(string, as: type) else { return nil }
            self = box
        }
    }

    private static func parseStructured(_ string: String, as type: FlagValueType)
        -> FlagValueBox?
    {
        switch type {
        case .date, .url:
            return FlagValueBox(jsonValue: string, as: type)

        default:
            guard
                let object = try? JSONSerialization.jsonObject(
                    with: Data(string.utf8),
                    options: [.fragmentsAllowed]
                )
            else { return nil }
            return FlagValueBox(jsonValue: object, as: type)
        }
    }
}
