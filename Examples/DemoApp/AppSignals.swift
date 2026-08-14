import FeatureFlag

/// Signals about the remote configuration this build is running on.
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

/// A second group, because one enum with everything in it stops scaling the moment an
/// app has more than a handful.
///
/// Filing them by type rather than by a label is what keeps each `switch` in the host
/// small and exhaustive: the configuration handler never has to mention caches.
public enum CacheSignal: String, FlagSignal {

    case purgeImageCache
    case purgeEverything

    public var signalDescription: String {
        switch self {
        case .purgeImageCache: return "Purge the image cache"
        case .purgeEverything: return "Purge everything"
        }
    }

    /// The demo builds its formatters and caches once at launch, so emptying them takes
    /// hold immediately in memory but the app looks unchanged until it starts again.
    public var requiresRestart: Bool { self == .purgeEverything }
}
