import XCTest

@testable import FeatureFlag

/// Two config layers per environment — a bundled local one and a fetched remote one —
/// kept in step with the environment the app is in.
///
/// Precedence within the pair is remote over local; both sit above the compiled
/// defaults and below any by-hand override.
final class EnvironmentConfigurationTests: XCTestCase {

    private enum Env: String { case staging, production }

    private func pole(_ config: EnvironmentConfiguration<Env>) -> FlagPole<EnvFlags> {
        FlagPole(EnvFlags.self, sources: config.sources)
    }

    // MARK: - Layering and precedence

    func testRemoteWinsOverLocalWhichWinsOverTheDefault() async throws {
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in Data(#"{ "pageSize": 20, "label": "local" }"#.utf8) },
            remote: { (_: Env) in Data(#"{ "pageSize": 25 }"#.utf8) }
        )
        let flags = pole(config)

        _ = await config.load(.staging)

        XCTAssertEqual(flags.pageSize, 25, "remote wins where both set it")
        XCTAssertEqual(flags.label, "local", "local wins where remote is silent")
        XCTAssertFalse(flags.beta, "neither set it — the compiled default")
    }

    func testProvenanceNamesTheLayerEachValueCameFrom() async throws {
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in Data(#"{ "label": "local" }"#.utf8) },
            remote: { (_: Env) in Data(#"{ "pageSize": 25 }"#.utf8) }
        )
        let flags = pole(config)
        _ = await config.load(.staging)

        XCTAssertEqual(flags.resolution(for: "page-size", as: .int).sourceName, "Remote")
        XCTAssertEqual(flags.resolution(for: "label", as: .string).sourceName, "Local")
        XCTAssertTrue(flags.resolution(for: "beta", as: .bool).isDefault)
    }

    // MARK: - Switching environments

    func testSwitchingClearsThePreviousEnvironmentsValues() async throws {
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (env: Env) in
                env == .staging ? Data(#"{ "label": "staging-local" }"#.utf8) : nil
            },
            remote: { (env: Env) in
                env == .staging ? Data(#"{ "pageSize": 25 }"#.utf8) : Data(#"{ "beta": true }"#.utf8)
            }
        )
        let flags = pole(config)

        _ = await config.load(.staging)
        XCTAssertEqual(flags.pageSize, 25)
        XCTAssertEqual(flags.label, "staging-local")

        _ = await config.load(.production)

        XCTAssertEqual(flags.pageSize, 10, "staging's remote value is gone")
        XCTAssertEqual(flags.label, "prod", "staging's local value is gone")
        XCTAssertTrue(flags.beta, "production's remote value is applied")
    }

    // MARK: - A layer that is absent or fails

    func testAnAbsentLocalLayerLeavesTheRemoteAndDefaults() async throws {
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in nil },   // no bundled config for this environment
            remote: { (_: Env) in Data(#"{ "pageSize": 25 }"#.utf8) }
        )
        let flags = pole(config)

        let outcome = await config.load(.staging)

        guard case .absent = outcome.local else {
            return XCTFail("expected the local layer absent, got \(outcome.local)")
        }
        XCTAssertTrue(outcome.remote.isApplied)
        XCTAssertEqual(flags.pageSize, 25)
        XCTAssertEqual(flags.label, "prod")
    }

    func testAFailedRemoteFetchFallsBackToTheLocalLayer() async throws {
        struct Offline: Error {}
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in Data(#"{ "pageSize": 20, "label": "local" }"#.utf8) },
            remote: { (_: Env) in throw Offline() }
        )
        let flags = pole(config)

        let outcome = await config.load(.staging)

        XCTAssertTrue(outcome.local.isApplied)
        guard case .failed = outcome.remote else {
            return XCTFail("expected the remote layer to fail, got \(outcome.remote)")
        }
        XCTAssertEqual(flags.pageSize, 20, "the local layer stands in for the missing remote")
    }

    func testAFailedRemoteDoesNotLeaveStaleValuesFromThePreviousEnvironment() async throws {
        struct Offline: Error {}
        var online = true
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in nil },
            remote: { (env: Env) in
                if env == .production, online == false { throw Offline() }
                return Data(#"{ "pageSize": 25 }"#.utf8)
            }
        )
        let flags = pole(config)

        _ = await config.load(.staging)
        XCTAssertEqual(flags.pageSize, 25)

        online = false
        _ = await config.load(.production)

        // Not 25: an app labelled production must not run yesterday's staging values.
        XCTAssertEqual(flags.pageSize, 10, "a failed fetch falls to defaults, not stale values")
    }

    // MARK: - Malformed config

    func testAMalformedLayerIsReportedAndDoesNotApply() async throws {
        let config = EnvironmentConfiguration(
            EnvFlags.self,
            local: { (_: Env) in Data("{ not json".utf8) },
            remote: { (_: Env) in nil }
        )
        let flags = pole(config)

        let outcome = await config.load(.staging)

        guard case .failed = outcome.local else {
            return XCTFail("expected the local layer to fail, got \(outcome.local)")
        }
        XCTAssertEqual(flags.pageSize, 10)
    }
}

// MARK: - Fixtures

@FlagContainer
private struct EnvFlags {

    @Flag(default: 10, description: "Page size", remoteKey: "pageSize")
    var pageSize: Int

    @Flag(default: false, description: "Beta", remoteKey: "beta")
    var beta: Bool

    @Flag(default: "prod", description: "Label", remoteKey: "label")
    var label: String
}
