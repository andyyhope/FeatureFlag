/// An instruction a companion app can send to its host.
///
/// ```swift
/// enum AppEvent: String, FlagEvent {
///     case refetchRemoteConfiguration
///     case purgeCache
/// }
/// ```
///
/// Declaring it as an enum is what gives the host an exhaustive `switch`: add a case
/// and the compiler shows you where to handle it.
///
/// Events carry no payload. That is a deliberate limit rather than a missing feature —
/// state belongs in flags, which the companion can already edit, and events are verbs.
/// "Re-fetch for staging" is the `environment` flag plus a bare `refetch`, not an event
/// with an argument.
public protocol FlagEvent: RawRepresentable, CaseIterable, Hashable, Sendable
where RawValue == String {

    /// What to call this on a button. Defaults to the raw value.
    var eventDescription: String { get }
}

extension FlagEvent {
    public var eventDescription: String { rawValue }
}

public enum FlagEventError: Error, Equatable {

    /// The host did not confirm handling within the timeout.
    ///
    /// Deliberately not called `hostNotRunning`: a missing acknowledgement is also what
    /// you see if the host is running but slow, still launching, or the notification was
    /// coalesced. Reporting it as certainty would be a lie the caller then shows someone.
    case notAcknowledged

    /// The App Group could not be opened, so there is nothing to send through.
    case unavailableAppGroup(String)
}
