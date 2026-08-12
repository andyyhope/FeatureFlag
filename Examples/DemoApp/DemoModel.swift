import Combine
import FeatureFlag
import Foundation

/// Holds everything the demo screen needs: the pole, the remote source it can feed, and
/// a Combine subscription so the framework's publishers are shown rather than described.
@MainActor
final class DemoModel: ObservableObject {

    let flags: FlagPole<AppFlags>

    /// Which bundled payload is currently applied, if any.
    @Published private(set) var appliedConfiguration: RemoteConfiguration?

    /// Why the last apply was rejected. Import and remote payloads are both
    /// all-or-nothing, so this is the whole story, not the first line of it.
    @Published private(set) var rejection: String?

    /// Proof the Combine publishers work: every change to one flag, counted as it
    /// arrives rather than read on redraw.
    @Published private(set) var onboardingChanges = 0

    private let remote: RemoteOverrideSource
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let remote = RemoteOverrideSource(AppFlags.self, name: "Remote")
        self.remote = remote

        // Order is the precedence. The companion's overrides sit above the backend, so
        // a value set by hand for testing survives the next payload.
        var sources: [any FlagValueSource] = []
        if let shared = UserDefaultsSource(appGroup: demoAppGroup, name: "Companion") {
            sources.append(shared)
        }
        sources.append(remote)

        self.flags = FlagPole(AppFlags.self, sources: sources, applicationName: "Demo")

        flags.flags.$newOnboarding.publisher
            .dropFirst()  // the publisher replays the current value on subscribe
            .sink { [weak self] _ in self?.onboardingChanges += 1 }
            .store(in: &cancellables)
    }

    /// Stands in for "your app downloaded a config and handed over the bytes".
    func apply(_ configuration: RemoteConfiguration) {
        do {
            try remote.apply(configuration.data, format: .json)
            appliedConfiguration = configuration
            rejection = nil
        } catch {
            appliedConfiguration = nil
            rejection = Self.describe(error)
        }
        objectWillChange.send()
    }

    func clearRemote() {
        remote.clear()
        appliedConfiguration = nil
        rejection = nil
        objectWillChange.send()
    }

    /// A rejection is only useful if it names the field and the reason.
    private static func describe(_ error: Error) -> String {
        guard case let RemoteOverrideError.rejected(problems) = error else {
            return "\(error)"
        }
        return problems
            .map { problem in
                switch problem.kind {
                case .typeMismatch:
                    return "\(problem.remoteKey) — wrong type for \(problem.key)"
                case .unknownCase:
                    return "\(problem.remoteKey) — not a case \(problem.key) can represent"
                case .unknownFlag:
                    return "\(problem.key) — no such flag in this app"
                }
            }
            .joined(separator: "\n")
    }
}
