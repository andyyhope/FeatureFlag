/// The type a flag declares, independent of any particular value.
///
/// Descriptors carry this so that a companion app can render the right editor, and so
/// that remote payloads can be validated strictly before anything is applied.
public enum FlagValueType: Hashable, Sendable, Codable {
    case bool
    case int
    case double
    case float
    case string
    case data
    case date
    case url
    indirect case array(FlagValueType)
    indirect case dictionary(FlagValueType)
}
