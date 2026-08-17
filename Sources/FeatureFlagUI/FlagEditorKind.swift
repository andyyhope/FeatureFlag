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
    /// An array of values that each have a control of their own, edited a row at a time.
    ///
    /// Carries the element's type, which is what lets the editor pick the right control
    /// for a row without ever seeing the host's Swift types.
    indirect case list(element: FlagValueType)

    /// A list of fixed-shape records, edited a record at a time.
    ///
    /// Carries the fields, which is what lets the editor give each one the control its
    /// type deserves without ever seeing the host's Swift types.
    case records([FlagRecordField])

    /// Everything else structural — dictionaries, and arrays whose elements are
    /// themselves collections — edited as JSON text.
    case json
}

extension FlagEditorKind {

    /// Whether this editor needs a wrapping block rather than a single line.
    ///
    /// Base64 and JSON are both long and read structurally; a single line can only ever
    /// show a fragment. Everything else is a value that fits.
    public var wantsWrappingEditor: Bool {
        switch self {
        case .data, .json: return true
        default: return false
        }
    }
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
        // A record list is a string to everything else in the framework, and it takes
        // the shape published beside it to know it is anything more.
        if let recordShape, recordShape.isEmpty == false {
            return .records(recordShape)
        }
        switch valueType {
        case .bool: return .toggle
        case .int: return .integer
        case .double, .float: return .decimal
        case .string: return .text
        case .date: return .date
        case .url: return .url
        case .data: return .data
        case let .array(element):
            // An array of scalars is a list of controls. An array of arrays is a shape
            // no row-per-element editor reads well, so it stays JSON.
            switch element {
            case .array, .dictionary: return .json
            default: return .list(element: element)
            }

        case .dictionary:
            return .json
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
