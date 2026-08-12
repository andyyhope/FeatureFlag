import Foundation

/// Carries events one way, from a companion app to its host.
///
/// iOS gives third-party apps no XPC and no way to wake another app, so this is built
/// from the two things that do cross the sandbox: an App Group both apps can read, and
/// a Darwin notification that carries no payload but does cross process boundaries. The
/// event name goes in the shared store; the notification rings the bell.
///
/// **Events reach a running host only.** A suspended or terminated app cannot receive a
/// Darwin notification, and nothing in iOS will wake it, so an event sent to an app that
/// is not running is lost rather than queued. ``send(_:timeout:)`` is how you find out.
///
/// ```swift
/// // companion
/// let channel = FlagEventChannel(appGroup: "group.example.flags")!
/// try await channel.send(AppEvent.refetchRemoteConfiguration, timeout: 2)
///
/// // host
/// let subscription = channel.observe(AppEvent.self) { event in
///     switch event {
///     case .refetchRemoteConfiguration: …
///     }
/// }
/// ```
public final class FlagEventChannel: @unchecked Sendable {

    private enum Key {
        static let event = "featureflag.event"
        static let sequence = "featureflag.event.sequence"
        static let handled = "featureflag.event.handled"
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
        self.init(defaults: defaults, notificationName: "\(groupIdentifier).featureflag.event")
    }

    public init(defaults: UserDefaults, notificationName: String) {
        self.defaults = defaults
        self.bell = notificationName
        self.acknowledgementBell = notificationName + ".ack"
    }

    // MARK: - Sending

    /// Sends an event without waiting to learn whether anything received it.
    ///
    /// Nothing is thrown and nothing is reported: a Darwin notification has no delivery
    /// receipt. Use ``send(_:timeout:)`` when the caller needs to know.
    public func send(_ event: some FlagEvent) {
        _ = write(event)
        DarwinNotificationCenter.post(bell)
    }

    /// Sends an event and waits for the host to confirm it handled it.
    ///
    /// Throws ``FlagEventError/notAcknowledged`` if no confirmation arrives in time —
    /// which usually means the host is not running, but see that case's note.
    public func send(_ event: some FlagEvent, timeout: TimeInterval) async throws {
        let sequence = write(event)

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
                    continuation.resume(throwing: FlagEventError.notAcknowledged)
                }
            }
        }
    }

    /// Writes the event and returns the sequence number it was given.
    @discardableResult
    private func write(_ event: some FlagEvent) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let sequence = defaults.integer(forKey: Key.sequence) + 1
        defaults.set(sequence, forKey: Key.sequence)
        defaults.set(["sequence": sequence, "name": event.rawValue], forKey: Key.event)
        return sequence
    }

    // MARK: - Receiving

    /// Calls `handler` on the main queue whenever the companion sends an event of this
    /// type, for as long as the returned subscription is held.
    ///
    /// An event this build cannot represent — a newer companion sending a case that does
    /// not exist here — is skipped and deliberately left unacknowledged, so the sender
    /// learns it was not handled rather than being told it was.
    public func observe<Event: FlagEvent>(
        _ type: Event.Type,
        handler: @escaping @Sendable (Event) -> Void
    ) -> FlagEventSubscription {
        let observer = DarwinNotificationCenter.observe(bell) { [weak self] in
            self?.drain(type, handler: handler)
        }
        return FlagEventSubscription(observer: observer)
    }

    private func drain<Event: FlagEvent>(
        _ type: Event.Type,
        handler: @escaping @Sendable (Event) -> Void
    ) {
        lock.lock()
        guard
            let record = defaults.dictionary(forKey: Key.event),
            let sequence = record["sequence"] as? Int,
            let name = record["name"] as? String,
            sequence > defaults.integer(forKey: Key.handled)
        else {
            lock.unlock()
            return
        }

        // Recorded before the handler runs. A Darwin notification can arrive more than
        // once for a single post, and re-running "purge the cache" because the OS
        // coalesced differently would be its own kind of bug.
        defaults.set(sequence, forKey: Key.handled)
        lock.unlock()

        guard let event = Event(rawValue: name) else { return }

        DispatchQueue.main.async {
            handler(event)
            DarwinNotificationCenter.post(self.acknowledgementBell)
        }
    }

    /// The highest sequence number the host has handled.
    var handledSequence: Int {
        lock.lock()
        defer { lock.unlock() }
        return defaults.integer(forKey: Key.handled)
    }
}

/// Holds an event subscription open. Releasing it stops delivery.
public final class FlagEventSubscription {

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
