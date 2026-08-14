#if os(iOS) || os(macOS)

    import FeatureFlag
    import Foundation

    /// How a group of signals is laid out.
    public enum FlagSignalGroupDisplay: Hashable, Sendable {

        /// Flat below a handful, its own screen above one. The threshold is
        /// ``FlagSignalGroup/automaticNestingThreshold``.
        case automatic

        /// Always its own screen, however few it holds.
        case nested

        /// Always a section on the main list, however many.
        case flat
    }

    /// A named set of signals.
    ///
    /// An app with four signals wants them in a list. An app with forty wants them filed,
    /// and filing them by *type* rather than by a label means each group is a real Swift
    /// boundary: the host switches over one enum at a time, exhaustively, and adding a
    /// case tells you where to handle it.
    ///
    /// ```swift
    /// enum CacheSignal: String, FlagSignal { case purgeImages, purgeAll }
    /// enum SessionSignal: String, FlagSignal { case signOut }
    ///
    /// .signals([
    ///     .group("Caches", CacheSignal.self),
    ///     .group("Session", SessionSignal.self),
    /// ], appGroup: "group.com.example.flags")
    /// ```
    public struct FlagSignalGroup: Identifiable {

        /// Above this many signals, an ``FlagSignalGroupDisplay/automatic`` group gets a
        /// screen of its own rather than a section. Six fits on a phone beside the delay
        /// picker without scrolling; change it if your rows are longer than mine.
        public static var automaticNestingThreshold = 6

        public let id: String
        public let title: String
        public let display: FlagSignalGroupDisplay

        /// The group's signals, erased so groups of different types can sit in one list.
        let signals: [ErasedSignal]

        /// Whether this group should be pushed rather than shown inline.
        var isNested: Bool {
            switch display {
            case .nested: return true
            case .flat: return false
            case .automatic: return signals.count > Self.automaticNestingThreshold
            }
        }
    }

    extension FlagSignalGroup {

        /// A group of every case in one signal type.
        ///
        /// - Parameters:
        ///   - title: The section header, or the row and screen title when nested.
        ///   - type: Your signal enum. Its `allCases` become the group's contents.
        ///   - display: Defaults to flat below
        ///     ``automaticNestingThreshold`` signals and nested above it.
        public static func group<Signal: FlagSignal>(
            _ title: String,
            _ type: Signal.Type,
            display: FlagSignalGroupDisplay = .automatic
        ) -> FlagSignalGroup {
            FlagSignalGroup(
                id: String(describing: type),
                title: title,
                display: display,
                signals: Signal.allCases.map(ErasedSignal.init)
            )
        }
    }

    /// One signal, with its type forgotten.
    ///
    /// Sending stays type-safe: the closure captures the concrete case, so it reaches
    /// `FlagSignalChannel.send(_:timeout:)` as itself rather than as a raw string.
    struct ErasedSignal: Identifiable, Hashable {

        let id: String
        let description: String
        let requiresRestart: Bool

        private let send: @Sendable (FlagSignalChannel, TimeInterval) async throws -> Void

        init<Signal: FlagSignal>(_ signal: Signal) {
            self.id = signal.rawValue
            self.description = signal.signalDescription
            self.requiresRestart = signal.requiresRestart
            self.send = { channel, timeout in
                try await channel.send(signal, timeout: timeout)
            }
        }

        func send(over channel: FlagSignalChannel, timeout: TimeInterval) async throws {
            try await send(channel, timeout)
        }

        static func == (lhs: ErasedSignal, rhs: ErasedSignal) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    extension Array where Element == FlagSignalGroup {

        /// The first raw value claimed by signals in more than one group.
        ///
        /// A signal travels as its raw value and nothing else, so two groups both
        /// defining `purge` means the host's observers both fire for one press. There is
        /// no correct behaviour to pick between them.
        var duplicateSignalID: String? {
            var seen = Set<String>()
            for group in self {
                for signal in group.signals where seen.insert(signal.id).inserted == false {
                    return signal.id
                }
            }
            return nil
        }
    }

#endif
