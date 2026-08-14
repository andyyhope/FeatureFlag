/// An instruction a companion app can send to its host.
///
/// ```swift
/// enum AppSignal: String, FlagSignal {
///     case refetchRemoteConfiguration
///     case purgeCache
/// }
/// ```
///
/// Declaring it as an enum is what gives the host an exhaustive `switch`: add a case
/// and the compiler shows you where to handle it.
///
/// Signals carry no payload. That is a deliberate limit rather than a missing feature —
/// state belongs in flags, which the companion can already edit, and signals are verbs.
/// "Re-fetch for staging" is the `environment` flag plus a bare `refetch`, not a signal
/// with an argument.
public protocol FlagSignal: RawRepresentable, CaseIterable, Hashable, Sendable
where RawValue == String {

    /// What to call this on a button. Defaults to the raw value.
    var signalDescription: String { get }

    /// Whether the host has to be relaunched before this takes effect. Defaults to
    /// `false`.
    ///
    /// A handled signal usually means something visibly changed. Some do not: purging a
    /// cache the app read into memory at launch, or swapping a dependency built during
    /// start-up, is done the moment the handler runs and invisible until the next launch.
    /// Saying so is the difference between "nothing happened" and "nothing happened yet".
    var requiresRestart: Bool { get }
}

extension FlagSignal {
    public var signalDescription: String { rawValue }
    public var requiresRestart: Bool { false }
}

public enum FlagSignalError: Error, Equatable {

    /// The host did not confirm handling within the timeout.
    ///
    /// Deliberately not called `hostNotRunning`: a missing acknowledgement is also what
    /// you see if the host is running but slow, still launching, or the notification was
    /// coalesced. Reporting it as certainty would be a lie the caller then shows someone.
    case notAcknowledged

    /// The App Group could not be opened, so there is nothing to send through.
    case unavailableAppGroup(String)
}
