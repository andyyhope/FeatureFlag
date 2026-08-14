import Foundation

/// Carries signals one way, from a companion app to its host.
///
/// iOS gives third-party apps no XPC and no way to wake another app, so this is built
/// from the two things that do cross the sandbox: an App Group both apps can read, and
/// a Darwin notification that carries no payload but does cross process boundaries. The
/// signal name goes in the shared store; the notification rings the bell.
///
/// **Signals reach a running host only.** A suspended or terminated app cannot receive a
/// Darwin notification, and nothing in iOS will wake it, so a signal sent to an app that
/// is not running is lost rather than queued. ``send(_:timeout:)`` is how you find out.
///
/// ```swift
/// // companion
/// let channel = FlagSignalChannel(appGroup: "group.example.flags")!
/// try await channel.send(AppSignal.refetchRemoteConfiguration, timeout: 2)
///
/// // host
/// let subscription = channel.observe(AppSignal.self) { signal in
///     switch signal {
///     case .refetchRemoteConfiguration: …
///     }
/// }
/// ```
public final class FlagSignalChannel: @unchecked Sendable {

    private enum Key {
        static let signal = "featureflag.signal"
        static let sequence = "featureflag.signal.sequence"
        static let handled = "featureflag.signal.handled"
    }

    private let defaults: UserDefaults
    private let bell: String
    private let acknowledgementBell: String
    private let lock = NSLock()

    /// A channel over an App Group both apps declare in their entitlements.
    ///
    /// Returns `nil` when the suite cannot be opened, which in practice means the group
    /// is missing from this target's entitlements.
    public convenience init?(appGroup groupIdentifier: String) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return nil }
        self.init(defaults: defaults, notificationName: "\(groupIdentifier).featureflag.signal")
    }

    public init(defaults: UserDefaults, notificationName: String) {
        self.defaults = defaults
        self.bell = notificationName
        self.acknowledgementBell = notificationName + ".ack"
    }

    // MARK: - Sending

    /// Sends a signal without waiting to learn whether anything received it.
    ///
    /// Nothing is thrown and nothing is reported: a Darwin notification has no delivery
    /// receipt. Use ``send(_:timeout:)`` when the caller needs to know.
    public func send(_ signal: some FlagSignal) {
        _ = write(signal)
        DarwinNotificationCenter.post(bell)
    }

    /// Sends a signal and waits for the host to confirm it handled it.
    ///
    /// Throws ``FlagSignalError/notAcknowledged`` if no confirmation arrives in time —
    /// which usually means the host is not running, but see that case's note.
    public func send(_ signal: some FlagSignal, timeout: TimeInterval) async throws {
        let sequence = write(signal)

        try await withCheckedThrowingContinuation { continuation in
            let resumed = Resumed()

            // Registered before the bell is rung: an ack that arrives immediately must
            // not land before anyone is listening for it.
            let observer = DarwinNotificationCenter.observe(acknowledgementBell) { [weak self] in
                guard let self, self.handledSequence >= sequence else { return }
                if resumed.claim() { continuation.resume() }
            }

            DarwinNotificationCenter.post(bell)

            // A host already past this sequence — an ack sent before the observer was
            // registered — still counts.
            if handledSequence >= sequence, resumed.claim() {
                _ = observer
                continuation.resume()
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                _ = observer
                if resumed.claim() {
                    continuation.resume(throwing: FlagSignalError.notAcknowledged)
                }
            }
        }
    }

    /// Writes the signal and returns the sequence number it was given.
    @discardableResult
    private func write(_ signal: some FlagSignal) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let sequence = defaults.integer(forKey: Key.sequence) + 1
        defaults.set(sequence, forKey: Key.sequence)
        defaults.set(["sequence": sequence, "name": signal.rawValue], forKey: Key.signal)
        return sequence
    }

    // MARK: - Receiving

    /// Calls `handler` on the main queue whenever the companion sends a signal of this
    /// type, for as long as the returned subscription is held.
    ///
    /// A signal this build cannot represent — a newer companion sending a case that does
    /// not exist here — is skipped and deliberately left unacknowledged, so the sender
    /// learns it was not handled rather than being told it was.
    public func observe<Signal: FlagSignal>(
        _ type: Signal.Type,
        handler: @escaping @Sendable (Signal) -> Void
    ) -> FlagSignalSubscription {
        let observer = DarwinNotificationCenter.observe(bell) { [weak self] in
            self?.drain(type, handler: handler)
        }
        return FlagSignalSubscription(observer: observer)
    }

    private func drain<Signal: FlagSignal>(
        _ type: Signal.Type,
        handler: @escaping @Sendable (Signal) -> Void
    ) {
        let observerKey = Self.handledKey(for: type)

        lock.lock()
        guard
            let record = defaults.dictionary(forKey: Key.signal),
            let sequence = record["sequence"] as? Int,
            let name = record["name"] as? String,
            sequence > defaults.integer(forKey: observerKey)
        else {
            lock.unlock()
            return
        }

        // Recorded before the handler runs. A Darwin notification can arrive more than
        // once for a single post, and re-running "purge the cache" because the OS
        // coalesced differently would be its own kind of bug.
        //
        // Per observer, though. A host that groups its signals declares an enum per
        // group and observes each one, and every observer has to get a look at every
        // event: with a single shared watermark the first to wake claimed the event,
        // failed to represent it, and dropped it on the floor.
        defaults.set(sequence, forKey: observerKey)
        lock.unlock()

        guard let signal = Signal(rawValue: name) else { return }

        DispatchQueue.main.async {
            handler(signal)

            // Only once a handler has actually run: the shared watermark is what the
            // sender's acknowledgement waits on, so advancing it for a signal this
            // observer could not represent would report success for a dropped event.
            self.recordHandled(sequence)
            DarwinNotificationCenter.post(self.acknowledgementBell)
        }
    }

    /// Where an observer of this type records what it has already seen.
    ///
    /// Keyed by type name, so renaming a signal enum resets its watermark and the next
    /// event is delivered once more than it strictly should be. Harmless, and cheaper
    /// than asking every caller for a stable identifier.
    private static func handledKey<Signal: FlagSignal>(for type: Signal.Type) -> String {
        "\(Key.handled).\(String(describing: type))"
    }

    private func recordHandled(_ sequence: Int) {
        lock.lock()
        defer { lock.unlock() }
        if sequence > defaults.integer(forKey: Key.handled) {
            defaults.set(sequence, forKey: Key.handled)
        }
    }

    /// The highest sequence number the host has handled.
    var handledSequence: Int {
        lock.lock()
        defer { lock.unlock() }
        return defaults.integer(forKey: Key.handled)
    }
}

/// Holds a signal subscription open. Releasing it stops delivery.
public final class FlagSignalSubscription {

    private let observer: DarwinNotificationObserver

    init(observer: DarwinNotificationObserver) {
        self.observer = observer
    }
}

/// One-shot latch, so a continuation is resumed exactly once no matter which of the
/// acknowledgement, the fast path or the timeout gets there first.
private final class Resumed: @unchecked Sendable {

    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard hasResumed == false else { return false }
        hasResumed = true
        return true
    }
}
