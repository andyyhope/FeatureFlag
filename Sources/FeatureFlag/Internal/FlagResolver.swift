import Combine
import Foundation

/// Walks the source stack to answer "what is this flag's value, and who supplied it?".
///
/// Kept separate from ``FlagPole`` so the pole can hand a fully formed lookup to
/// its container at initialisation without any two-phase or force-unwrapped storage.
final class FlagResolver: FlagLookup, @unchecked Sendable {

    let keyEncoding: KeyEncoding

    private let sources: [any FlagValueSource]
    private let subject = PassthroughSubject<FlagChange, Never>()
    private var cancellables: Set<AnyCancellable> = []

    init(sources: [any FlagValueSource], keyEncoding: KeyEncoding) {
        self.sources = sources
        self.keyEncoding = keyEncoding

        for source in sources {
            source.changes
                .sink { [subject] change in subject.send(change) }
                .store(in: &cancellables)
        }
    }

    /// The first source holding a value of the right type wins.
    ///
    /// A stored value of the wrong type is skipped rather than surfaced, so a stale or
    /// hand-edited store degrades to the next source instead of to a crash.
    func resolution(for key: FlagKey, as type: FlagValueType) -> FlagResolution {
        for source in sources {
            guard let box = source.box(for: key, as: type), box.matches(type) else { continue }
            return FlagResolution(key: key, sourceName: source.sourceName, box: box)
        }
        return FlagResolution(key: key, sourceName: nil, box: nil)
    }

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        resolution(for: key, as: type).box
    }

    func changePublisher(for key: FlagKey) -> AnyPublisher<Void, Never> {
        subject
            .filter { $0.affects(key) }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Writes to the highest-priority source that accepts writes.
    func setOverride(_ box: FlagValueBox?, for key: FlagKey) throws {
        for source in sources {
            if let mutable = source as? any MutableFlagValueSource {
                try mutable.setBox(box, for: key)
                return
            }
        }
        throw FlagError.noMutableSource
    }
}

/// Where a flag's value came from.
public struct FlagResolution: Hashable, Sendable {

    public let key: FlagKey

    /// The source that supplied the value, or `nil` when nothing did and the compiled
    /// default applies.
    public let sourceName: String?

    /// The value that won, or `nil` when the compiled default applies.
    public let box: FlagValueBox?

    /// Whether the compiled default is in effect.
    public var isDefault: Bool { sourceName == nil }
}
