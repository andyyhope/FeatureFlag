import Combine

/// What changed in a source.
public enum FlagChange: Hashable, Sendable {

    /// Every key should be re-read. Sources that cannot describe their change more
    /// precisely — a whole remote payload landing, say — report this.
    case all

    /// Only these keys changed.
    case keys(Set<FlagKey>)

    func affects(_ key: FlagKey) -> Bool {
        switch self {
        case .all: return true
        case let .keys(keys): return keys.contains(key)
        }
    }
}

/// Supplies flag values to a ``SignalTower``.
///
/// A tower holds an ordered stack of these and asks each in turn, so the order of the
/// stack *is* the precedence.
public protocol FlagValueSource: AnyObject, Sendable {

    /// Identifies the source when explaining where a value came from.
    var sourceName: String { get }

    /// The value this source holds for a key.
    ///
    /// `type` is the flag's declared type, which lets a source stored in a loosely
    /// typed medium — `UserDefaults`, say — decode unambiguously rather than guess.
    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox?

    /// Emits whenever stored values change, including changes made by another process.
    var changes: AnyPublisher<FlagChange, Never> { get }
}

/// A source whose values can be changed at runtime — the companion app writing an
/// override, or an import landing.
public protocol MutableFlagValueSource: FlagValueSource {

    /// Stores a value, or removes it when `box` is `nil`.
    func setBox(_ box: FlagValueBox?, for key: FlagKey) throws
}

public enum FlagError: Error, Equatable {

    /// Nothing in the source stack can be written to.
    case noMutableSource

    /// A source refused a value it cannot represent.
    case unsupportedValue(FlagKey)
}
