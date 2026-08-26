import Combine
import FeatureFlag
import Foundation

/// Holds everything the demo screen needs: the pole, the environment configuration that
/// feeds its local and remote layers, and the Combine subscription that lets the
/// environment flag drive which config is loaded.
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
    @Published private(set) var lastSignal: String?
    @Published private(set) var purgedCaches = 0
    @Published private(set) var awaitingRelaunch = false

    private let config: EnvironmentConfiguration<DemoEnvironment>
    private let signals: FlagSignalChannel?
    private var signalSubscription: FlagSignalSubscription?
    private var cacheSignalSubscription: FlagSignalSubscription?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // The environment's two layers: a config bundled in the app, and one fetched for
        // it. The framework does no networking or file reading — these closures hand it
        // the bytes. `remote` is async because a real fetch would be.
        let config = EnvironmentConfiguration(
            AppFlags.self,
            mapper: DemoRemoteMapper(),
            localName: "Local",
            remoteName: "Remote",
            local: { environment in LocalConfiguration.forEnvironment(environment).data },
            remote: { environment in RemoteConfiguration.forEnvironment(environment).data }
        )
        self.config = config

        // Order is the precedence, highest first: a value set by hand in the companion
        // beats the backend, which beats the bundled local config, which beats the
        // compiled defaults. `config.sources` is [remote, local] in that order.
        var sources: [any FlagValueSource] = []
        if let shared = UserDefaultsSource(appGroup: demoAppGroup, name: "Companion") {
            sources.append(shared)
        } else {
            // Keeps the demo usable if the App Group is unavailable; the companion app
            // simply will not see anything.
            sources.append(SnapshotSource(name: "By hand"))
        }
        sources.append(contentsOf: config.sources)

        self.flags = FlagPole(AppFlags.self, sources: sources, applicationName: "Demo")
        self.signals = FlagSignalChannel(appGroup: demoAppGroup)

        // The environment flag drives which payload is applied. `publisher` replays the
        // current value on subscribe, so this also performs the initial fetch.
        flags.flags.$environment.publisher
            .removeDuplicates()
            .sink { [weak self] environment in
                Task { await self?.switchTo(environment) }
            }
            .store(in: &cancellables)

        flags.flags.$newOnboarding.publisher
            .dropFirst()
            .sink { [weak self] _ in self?.onboardingChanges += 1 }
            .store(in: &cancellables)

        // The companion can ask this app to do something, not just change what it reads.
        // One observer per group: each switch stays small and exhaustive, and every
        // observer sees every signal rather than the first one claiming them all.
        signalSubscription = signals?.observe(AppSignal.self) { [weak self] signal in
            MainActor.assumeIsolated { self?.handle(signal) }
        }
        cacheSignalSubscription = signals?.observe(CacheSignal.self) { [weak self] signal in
            MainActor.assumeIsolated { self?.handle(signal) }
        }
    }

    // MARK: - Signals from the companion

    private func handle(_ signal: AppSignal) {
        lastSignal = signal.signalDescription
        switch signal {
        case .refetchRemoteConfiguration:
            Task { await switchTo(flags.environment) }
        case .clearRemoteConfiguration:
            clearRemote()
        }
    }

    private func handle(_ signal: CacheSignal) {
        lastSignal = signal.signalDescription
        switch signal {
        case .purgeImageCache:
            // Visible immediately, so this one needs no relaunch.
            purgedCaches += 1

        case .purgeEverything:
            // Emptied now, rebuilt at launch — so nothing here looks different until
            // the app starts again. That is what the signal's requiresRestart says, and
            // why the companion reports "handled — relaunch to see it" rather than
            // leaving someone to conclude nothing happened.
            awaitingRelaunch = true
        }
    }

    // MARK: - Environment

    /// Loads both layers for an environment: the bundled local config, then the fetched
    /// remote one.
    ///
    /// The environment flag has no `remoteKey`. If it did, a staging payload could set
    /// the environment to production, which would mean the app should have loaded a
    /// different config — and loading *that* could set it back. Nothing in the framework
    /// stops you wiring that loop; leaving the key off is what prevents it.
    ///
    /// The coordinator clears each layer before loading it, so a failed fetch falls back
    /// to the local config, then the compiled defaults — never to the previous
    /// environment's values, which on an app labelled "staging" would look wrong to no
    /// one.
    func switchTo(_ environment: DemoEnvironment) async {
        let outcome = await config.load(environment)
        switch outcome.remote {
        case .applied:
            appliedConfiguration = .forEnvironment(environment)
            rejection = nil
        case .absent:
            appliedConfiguration = nil
            rejection = nil
        case let .failed(error):
            appliedConfiguration = nil
            rejection = Self.describe(error)
        }
        objectWillChange.send()
    }

    var environment: DemoEnvironment {
        get { flags.environment }
        set { try? flags.setOverride(newValue, for: flags.flags.$environment) }
    }

    // MARK: - Applying

    /// Stands in for "your app downloaded a config and handed over the bytes".
    func apply(_ configuration: RemoteConfiguration) {
        do {
            try config.remoteSource.apply(configuration.data, format: .json)
            appliedConfiguration = configuration
            rejection = nil
        } catch {
            appliedConfiguration = nil
            rejection = Self.describe(error)
        }
        objectWillChange.send()
    }

    /// Clears just the remote layer, leaving the bundled local config showing through —
    /// which is the local layer earning its place, rather than falling to raw defaults.
    func clearRemote() {
        config.remoteSource.clear()
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
                case .unknownKey:
                    return "\(problem.key) — no such flag in this app"
                }
            }
            .joined(separator: "\n")
    }
}
