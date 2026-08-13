import Combine
import FeatureFlag
import Foundation

/// Holds everything the demo screen needs: the pole, the remote source it feeds, and the
/// Combine subscription that lets the environment flag drive which payload is applied.
@MainActor
final class DemoModel: ObservableObject {

    let flags: FlagPole<AppFlags>

    /// Which payload is currently applied, if any.
    @Published private(set) var appliedConfiguration: RemoteConfiguration?

    /// Why the last apply was rejected. Remote payloads are all-or-nothing, so this is
    /// the whole story rather than the first line of it.
    @Published private(set) var rejection: String?

    /// Proof the publishers work: changes counted as they arrive, not read on redraw.
    @Published private(set) var onboardingChanges = 0

    /// The last signal the companion sent, so the demo can show it arriving.
    @Published private(set) var lastSignal: AppSignal?

    private let remote: RemoteOverrideSource
    private let signals: FlagSignalChannel?
    private var signalSubscription: FlagSignalSubscription?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let remote = RemoteOverrideSource(AppFlags.self, name: "Remote")
        self.remote = remote

        // Order is the precedence. Overrides sit above the backend, so a value set by
        // hand for testing survives the next payload.
        var sources: [any FlagValueSource] = []
        if let shared = UserDefaultsSource(appGroup: demoAppGroup, name: "Companion") {
            sources.append(shared)
        } else {
            // Keeps the demo usable if the App Group is unavailable; the companion app
            // simply will not see anything.
            sources.append(SnapshotSource(name: "Local"))
        }
        sources.append(remote)

        self.flags = FlagPole(AppFlags.self, sources: sources, applicationName: "Demo")
        self.signals = FlagSignalChannel(appGroup: demoAppGroup)

        // The environment flag drives which payload is applied. `publisher` replays the
        // current value on subscribe, so this also performs the initial fetch.
        flags.flags.$environment.publisher
            .removeDuplicates()
            .sink { [weak self] environment in self?.switchTo(environment) }
            .store(in: &cancellables)

        flags.flags.$newOnboarding.publisher
            .dropFirst()
            .sink { [weak self] _ in self?.onboardingChanges += 1 }
            .store(in: &cancellables)

        // The companion can ask this app to do something, not just change what it reads.
        signalSubscription = signals?.observe(AppSignal.self) { [weak self] signal in
            MainActor.assumeIsolated { self?.handle(signal) }
        }
    }

    // MARK: - Signals from the companion

    private func handle(_ signal: AppSignal) {
        lastSignal = signal
        switch signal {
        case .refetchRemoteConfiguration:
            switchTo(flags.environment)
        case .clearRemoteConfiguration:
            clearRemote()
        }
    }

    // MARK: - Environment

    /// Fetches and applies the payload for an environment.
    ///
    /// Two things here are the whole reason this is worth playing out.
    ///
    /// The environment flag has no `remoteKey`. If it did, a staging payload could set
    /// the environment to production, which would mean the app should have fetched a
    /// different payload — and applying *that* could set it back. Nothing in the
    /// framework stops you wiring that loop; leaving the key off is what prevents it.
    ///
    /// The old environment's values are cleared before the new ones are applied. That
    /// leaves a brief window on compiled defaults, which is deliberate: if the fetch
    /// fails, an app labelled "staging" running yesterday's production values is worse
    /// than one running its own defaults, because nothing about it looks wrong.
    func switchTo(_ environment: DemoEnvironment) {
        remote.clear()
        apply(.forEnvironment(environment))
    }

    var environment: DemoEnvironment {
        get { flags.environment }
        set { try? flags.setOverride(newValue, for: flags.flags.$environment) }
    }

    // MARK: - Applying

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
