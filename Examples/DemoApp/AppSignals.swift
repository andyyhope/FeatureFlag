import FeatureFlag

/// Signals the companion app can send to the demo.
///
/// Shared by both targets, so the companion sends `.refetchRemoteConfiguration` typed
/// and the host switches over it exhaustively — add a case and the compiler shows you
/// where to handle it.
///
/// No payloads. State belongs in flags: "re-fetch for staging" is the `environment`
/// flag, which the companion can already edit, followed by a bare re-fetch.
public enum AppSignal: String, FlagSignal {

    case refetchRemoteConfiguration
    case clearRemoteConfiguration

    public var signalDescription: String {
        switch self {
        case .refetchRemoteConfiguration: return "Re-fetch remote configuration"
        case .clearRemoteConfiguration: return "Clear remote configuration"
        }
    }
}
