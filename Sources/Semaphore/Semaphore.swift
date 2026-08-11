/// Semaphore — a Swift-native feature flag framework.
///
/// Declare flags with ``Flag`` and ``FlagGroup`` inside a type annotated with
/// `@FlagContainer`, then read them through a ``SignalTower``.
public enum Semaphore {
    /// The version of the on-disk schema and payload formats this build produces.
    public static let formatVersion = 1
}
