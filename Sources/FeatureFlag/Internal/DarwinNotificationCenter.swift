import Foundation

/// Payload-free notifications that cross process boundaries.
///
/// This is the only mechanism that tells a host app another process changed a shared
/// `UserDefaults` suite — `UserDefaults.didChangeNotification` does not fire for
/// external writes. It carries no data, so a recipient re-reads and diffs.
///
/// A suspended app never receives these, which is why sources also refresh when the
/// app returns to the foreground.
public enum DarwinNotificationCenter {

    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    /// Calls `handler` whenever `name` is posted, by this process or any other.
    ///
    /// Observation lasts as long as the returned token is held.
    public static func observe(
        _ name: String,
        handler: @escaping @Sendable () -> Void
    ) -> DarwinNotificationObserver {
        DarwinNotificationRegistry.shared.add(name: name, handler: handler)
    }
}

/// Keeps a Darwin observation alive. Releasing it stops the handler being called.
///
/// Sendable because everything it holds is immutable; the mutable state lives in the
/// registry behind a lock.
public final class DarwinNotificationObserver: Sendable {

    let id = UUID()
    let name: String

    init(name: String) {
        self.name = name
    }

    deinit {
        DarwinNotificationRegistry.shared.remove(id: id, name: name)
    }
}

/// The C callback carries no context pointer we can attach a closure to, so handlers
/// live here and are found by notification name.
private final class DarwinNotificationRegistry: @unchecked Sendable {

    static let shared = DarwinNotificationRegistry()

    private let lock = NSLock()
    private var handlers: [String: [UUID: @Sendable () -> Void]] = [:]

    func add(name: String, handler: @escaping @Sendable () -> Void) -> DarwinNotificationObserver {
        let observer = DarwinNotificationObserver(name: name)

        lock.lock()
        let isFirstForName = handlers[name] == nil
        handlers[name, default: [:]][observer.id] = handler
        lock.unlock()

        if isFirstForName {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                darwinNotificationCallback,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        return observer
    }

    func remove(id: UUID, name: String) {
        lock.lock()
        handlers[name]?.removeValue(forKey: id)
        if handlers[name]?.isEmpty == true {
            handlers[name] = nil
        }
        lock.unlock()
        // The CF observer is left registered: re-adding is cheap, and unregistering a
        // name another observer may be about to claim invites a race for no gain.
    }

    func fire(_ name: String) {
        lock.lock()
        let toCall = handlers[name]?.values.map { $0 } ?? []
        lock.unlock()

        for handler in toCall {
            handler()
        }
    }
}

private func darwinNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let name = name?.rawValue as String? else { return }
    DarwinNotificationRegistry.shared.fire(name)
}
