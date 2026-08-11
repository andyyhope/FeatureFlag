import Combine
import Foundation

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Reads and writes flag values in `UserDefaults`, optionally an App Group suite
/// shared with a companion app.
///
/// Values are stored natively — a `Bool` flag is a real `Bool` in the suite — so
/// `defaults read`, other frameworks and older builds can all still make sense of
/// them, and flags an app already stores by hand are adopted as they are.
///
/// Reading is type-directed. `UserDefaults` hands back `NSNumber` for booleans,
/// integers and doubles alike, so the flag's declared type is what makes decoding
/// unambiguous instead of a guess.
///
/// One platform caveat, verified rather than assumed: `UserDefaults` caches a key's
/// CoreFoundation type within a process. If a key that has held a number is then given
/// a boolean, it still reads back as a number until the process restarts — and no way
/// of writing the boolean (`NSNumber`, `kCFBooleanTrue`, a plain `Any`) avoids it.
/// This only bites if a flag changes its Swift type while keeping its key, which is a
/// breaking change to that flag's meaning in any case.
public final class UserDefaultsSource: MutableFlagValueSource, @unchecked Sendable {

    public let sourceName: String

    private let defaults: UserDefaults
    private let crossProcessNotificationName: String?
    private let subject = PassthroughSubject<FlagChange, Never>()

    private var darwinObserver: DarwinNotificationObserver?
    private var foregroundObserver: (any NSObjectProtocol)?

    public init(
        defaults: UserDefaults = .standard,
        name: String = "UserDefaults",
        crossProcessNotificationName: String? = nil
    ) {
        self.defaults = defaults
        self.sourceName = name
        self.crossProcessNotificationName = crossProcessNotificationName

        if let crossProcessNotificationName {
            darwinObserver = DarwinNotificationCenter.observe(crossProcessNotificationName) {
                [subject] in
                subject.send(.all)
            }
        }
        observeForeground()
    }

    /// A source backed by an App Group suite, wired for cross-process change
    /// notification.
    ///
    /// Returns `nil` when the suite cannot be opened, which in practice means the App
    /// Group is missing from the target's entitlements.
    public convenience init?(appGroup groupIdentifier: String, name: String = "App Group") {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return nil }
        self.init(
            defaults: defaults,
            name: name,
            crossProcessNotificationName: "\(groupIdentifier).featureflag.changed"
        )
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Reading and writing

    public func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        guard let object = defaults.object(forKey: key.rawValue) else { return nil }
        return FlagValueBox(propertyListValue: object, as: type)
    }

    public var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    public func setBox(_ box: FlagValueBox?, for key: FlagKey) throws {
        if let box {
            defaults.set(box.propertyListValue, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }

        subject.send(.keys([key]))

        if let crossProcessNotificationName {
            DarwinNotificationCenter.post(crossProcessNotificationName)
        }
    }

    /// Re-reads everything, announcing a wholesale change.
    ///
    /// Called automatically when the app returns to the foreground, because a
    /// suspended process misses the Darwin notifications sent while it was away.
    public func refresh() {
        subject.send(.all)
    }

    private func observeForeground() {
        #if canImport(UIKit) && !os(watchOS)
            let name = UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
            let name = NSApplication.didBecomeActiveNotification
        #else
            return
        #endif

        #if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [subject] _ in
                subject.send(.all)
            }
        #endif
    }
}

// MARK: - Property list conversion

extension FlagValueBox {

    /// The value to hand to `UserDefaults`.
    ///
    /// `URL` becomes its string form rather than an archived blob, so the suite stays
    /// human-readable and portable.
    var propertyListValue: Any {
        switch self {
        case let .bool(value): return value
        case let .int(value): return value
        case let .double(value): return value
        case let .float(value): return value
        case let .string(value): return value
        case let .data(value): return value
        case let .date(value): return value
        case let .url(value): return value.absoluteString
        case let .array(boxes): return boxes.map(\.propertyListValue)
        case let .dictionary(boxes): return boxes.mapValues(\.propertyListValue)
        }
    }

    /// Rebuilds a box from a property list value, guided by the flag's declared type.
    init?(propertyListValue object: Any, as type: FlagValueType) {
        switch type {
        // `UserDefaults` stores booleans as CFBoolean, which bridges to NSNumber like
        // every other number. Without discriminating, an Int of 1 reads as `true` and
        // a `true` reads as 1 — silent wrong answers rather than a fall-through to the
        // next source.
        case .bool:
            guard isPropertyListBoolean(object), let value = object as? Bool else { return nil }
            self = .bool(value)

        case .int:
            guard !isPropertyListBoolean(object), let value = object as? Int else { return nil }
            self = .int(value)

        case .double:
            guard !isPropertyListBoolean(object), let value = object as? Double else { return nil }
            self = .double(value)

        case .float:
            guard !isPropertyListBoolean(object), let value = object as? Float else { return nil }
            self = .float(value)

        case .string:
            guard let value = object as? String else { return nil }
            self = .string(value)

        case .data:
            guard let value = object as? Data else { return nil }
            self = .data(value)

        case .date:
            guard let value = object as? Date else { return nil }
            self = .date(value)

        case .url:
            guard let value = object as? String, let url = URL(string: value) else { return nil }
            self = .url(url)

        case let .array(element):
            guard let values = object as? [Any] else { return nil }
            var boxes = [FlagValueBox]()
            boxes.reserveCapacity(values.count)
            for value in values {
                guard let box = FlagValueBox(propertyListValue: value, as: element) else {
                    return nil
                }
                boxes.append(box)
            }
            self = .array(boxes)

        case let .dictionary(valueType):
            guard let values = object as? [String: Any] else { return nil }
            var boxes = [String: FlagValueBox](minimumCapacity: values.count)
            for (key, value) in values {
                guard let box = FlagValueBox(propertyListValue: value, as: valueType) else {
                    return nil
                }
                boxes[key] = box
            }
            self = .dictionary(boxes)
        }
    }
}

/// Whether a property list value is a boolean rather than a number.
///
/// `UserDefaults` stores booleans as CFBoolean, and both CFBoolean and CFNumber bridge
/// to `NSNumber`, so Swift casting alone cannot tell 1 from `true`. CoreFoundation can.
private func isPropertyListBoolean(_ object: Any) -> Bool {
    CFGetTypeID(object as CFTypeRef) == CFBooleanGetTypeID()
}
