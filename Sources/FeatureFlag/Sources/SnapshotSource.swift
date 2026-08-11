import Combine
import Foundation

/// An in-memory set of flag values.
///
/// Useful as the top of a stack in tests and previews, as the landing place for an
/// imported payload, and as a way to capture the current state of a tower.
public final class SnapshotSource: MutableFlagValueSource, @unchecked Sendable {

    public let sourceName: String

    private let lock = NSLock()
    private var storage: [FlagKey: FlagValueBox]
    private let subject = PassthroughSubject<FlagChange, Never>()

    public init(name: String = "Snapshot", values: [FlagKey: FlagValueBox] = [:]) {
        self.sourceName = name
        self.storage = values
    }

    public func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    public func setBox(_ box: FlagValueBox?, for key: FlagKey) throws {
        lock.lock()
        let changed = storage[key] != box
        storage[key] = box
        lock.unlock()

        if changed {
            subject.send(.keys([key]))
        }
    }

    /// Everything this snapshot holds.
    public var values: [FlagKey: FlagValueBox] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Replaces the entire contents in one step, reporting a single change.
    public func replaceAll(with values: [FlagKey: FlagValueBox]) {
        lock.lock()
        storage = values
        lock.unlock()
        subject.send(.all)
    }
}
