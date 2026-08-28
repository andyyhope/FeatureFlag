import Foundation

/// Two config layers per environment, kept in step with the environment the app is in:
/// a local one that ships with the app, and a remote one it fetches.
///
/// ```swift
/// let config = EnvironmentConfiguration(
///     AppFlags.self,
///     local:  { env in Bundle.main.data(named: "\(env).json") },
///     remote: { env in try await api.fetchConfig(for: env) }
/// )
/// let pole = FlagPole(AppFlags.self, sources: [companion] + config.sources)
///
/// // when the environment flag changes:
/// await config.load(.staging)   // local staging.json, then remote staging.json
/// ```
///
/// Precedence within the pair is **remote over local**: a value the backend sends for an
/// environment wins over the one bundled for it, and both win over the compiled default.
/// ``sources`` hands them back in that order, to splice into a pole's stack above the
/// defaults and below any by-hand override.
///
/// Switching environments **clears the previous one first**. A layer whose loader returns
/// `nil` or throws is left cleared rather than kept, so a failed fetch falls back to the
/// layer beneath — the local config, then the compiled defaults — instead of leaving an
/// app labelled *production* running yesterday's *staging* values, which is worse
/// because nothing about it looks wrong.
///
/// The framework does no networking and reads no files: you supply the bytes, it
/// decodes, validates, and layers them.
public final class EnvironmentConfiguration<Environment> {

    /// The bundled layer — a config that ships with the app. Above the compiled
    /// defaults, below the remote layer.
    public let localSource: RemoteOverrideSource

    /// The fetched layer — the higher of the pair.
    public let remoteSource: RemoteOverrideSource

    private let format: FlagPayloadFormat
    private let local: (Environment) throws -> Data?
    // A var so it can be rebound after the pole exists — see ``fetchRemote(_:)``.
    // Guarded by `lock`, alongside `epoch`.
    private var remote: (Environment) async throws -> Data?

    // A monotonic token so a slow load cannot apply over a newer one. Switching
    // environments quickly, with a slow fetch, could otherwise leave the new
    // environment showing the old one's values.
    private let lock = NSLock()
    private var epoch = 0

    /// Both layers in precedence order — remote first — to splice into a pole's stack.
    public var sources: [any FlagValueSource] { [remoteSource, localSource] }

    /// - Parameters:
    ///   - schema: The flag tree both layers validate against.
    ///   - format: How the config bytes are encoded. JSON by default.
    ///   - mapper: How a payload's shape maps onto flags. ``DotPathMapper`` by default.
    ///   - localName: The local layer's source name, for provenance.
    ///   - remoteName: The remote layer's source name, for provenance.
    ///   - local: The bytes of the local config for an environment, or `nil` when there
    ///     is none. Runs synchronously — it reads something already on the device.
    ///   - remote: The bytes of the remote config for an environment, or `nil` when there
    ///     is none. Runs `async` — this is your fetch. Omit it and set ``fetchRemote(_:)``
    ///     later when the fetch depends on a flag the local layer carries, since the pole
    ///     that resolves it does not exist yet at construction.
    public init(
        schema: FlagSchema,
        format: FlagPayloadFormat = .json,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        localName: String = "Local",
        remoteName: String = "Remote",
        local: @escaping (Environment) throws -> Data?,
        remote: @escaping (Environment) async throws -> Data? = { _ in nil }
    ) {
        self.localSource = RemoteOverrideSource(schema: schema, mapper: mapper, name: localName)
        self.remoteSource = RemoteOverrideSource(schema: schema, mapper: mapper, name: remoteName)
        self.format = format
        self.local = local
        self.remote = remote
    }

    /// Builds one for a container, describing it with the key encoding the pole will use.
    public convenience init<Root: FlagContainer>(
        _ type: Root.Type = Root.self,
        keyEncoding: KeyEncoding = .kebabcase,
        format: FlagPayloadFormat = .json,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        localName: String = "Local",
        remoteName: String = "Remote",
        local: @escaping (Environment) throws -> Data?,
        remote: @escaping (Environment) async throws -> Data? = { _ in nil }
    ) {
        self.init(
            schema: FlagSchema(Root.self, keyEncoding: keyEncoding),
            format: format,
            mapper: mapper,
            localName: localName,
            remoteName: remoteName,
            local: local,
            remote: remote
        )
    }

    /// Loads both layers for an environment: the local config, then the remote one.
    ///
    /// Each layer is cleared before it is loaded, so a loader that returns `nil` or
    /// throws leaves that layer empty and the one beneath it showing through. The result
    /// says what happened to each, since one can succeed while the other does not.
    @discardableResult
    public func load(_ environment: Environment) async -> LoadOutcome {
        lock.lock()
        epoch += 1
        let mine = epoch
        let remote = self.remote
        lock.unlock()

        let localOutcome = apply(to: localSource, epoch: mine) { try self.local(environment) }
        let remoteOutcome = await applyAsync(to: remoteSource, epoch: mine) {
            try await remote(environment)
        }
        return LoadOutcome(local: localOutcome, remote: remoteOutcome)
    }

    /// Supplies the remote layer's bytes, replacing any loader given at init.
    ///
    /// Set this after the pole exists when the fetch depends on a flag the local layer
    /// carries — the endpoint to fetch from, say. Capture the pole and read it in the
    /// closure: ``load(_:)`` applies the local layer before the loader runs, so a value
    /// it, or a layer above it, supplies is already resolvable.
    ///
    /// ```swift
    /// let pole = FlagPole(AppFlags.self, sources: [companion] + config.sources)
    /// config.fetchRemote { [pole] env in
    ///     try await api.fetch(pole.flags.checkout.remoteURL)   // resolved after local lands
    /// }
    /// ```
    public func fetchRemote(_ load: @escaping (Environment) async throws -> Data?) {
        lock.lock()
        remote = load
        lock.unlock()
    }

    /// Whether this load is still the most recent — nothing newer has started.
    private func isCurrent(_ mine: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return mine == epoch
    }

    // MARK: - Applying one layer

    private func apply(
        to source: RemoteOverrideSource,
        epoch mine: Int,
        loading load: () throws -> Data?
    ) -> LayerOutcome {
        source.clear()
        do {
            guard let data = try load() else { return .absent }
            guard isCurrent(mine) else { return .superseded }
            try source.apply(data, format: format)
            return .applied
        } catch {
            return .failed(error)
        }
    }

    private func applyAsync(
        to source: RemoteOverrideSource,
        epoch mine: Int,
        loading load: () async throws -> Data?
    ) async -> LayerOutcome {
        source.clear()
        do {
            guard let data = try await load() else { return .absent }
            // Re-checked after the await: a newer load may have started and now owns the
            // source, so a stale result must not be written over it.
            guard isCurrent(mine) else { return .superseded }
            try source.apply(data, format: format)
            return .applied
        } catch {
            return .failed(error)
        }
    }
}

/// What became of each layer when an environment was loaded.
public struct LoadOutcome {

    public let local: LayerOutcome
    public let remote: LayerOutcome

    public init(local: LayerOutcome, remote: LayerOutcome) {
        self.local = local
        self.remote = remote
    }

    /// Whether both layers loaded as far as they could — applied, or absent because
    /// there was nothing to load. False if either failed.
    public var isComplete: Bool { local.isComplete && remote.isComplete }
}

/// What became of one config layer.
public enum LayerOutcome {

    /// The config was loaded and applied.
    case applied

    /// The loader returned `nil` — there is no config of this kind for this environment.
    case absent

    /// The loader threw, or the config it returned was rejected. The layer is cleared.
    case failed(any Error)

    /// A newer load started before this one finished, and now owns the layer, so this
    /// result was dropped rather than written over it.
    case superseded

    public var isApplied: Bool {
        if case .applied = self { return true }
        return false
    }

    /// Not a failure: applied, legitimately absent, or dropped because a newer load
    /// took over.
    public var isComplete: Bool {
        switch self {
        case .applied, .absent, .superseded: return true
        case .failed: return false
        }
    }
}
