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
