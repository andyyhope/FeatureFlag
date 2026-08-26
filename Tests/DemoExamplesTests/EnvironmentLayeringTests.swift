import FeatureFlag
import XCTest

@testable import DemoExamples

/// The demo's two config layers, built the way DemoModel builds them: a bundled local
/// config beneath a fetched remote one, per environment.
final class EnvironmentLayeringTests: XCTestCase {

    private func makeConfig() -> EnvironmentConfiguration<DemoEnvironment> {
        EnvironmentConfiguration(
            AppFlags.self,
            mapper: DemoRemoteMapper(),
            localName: "Local",
            remoteName: "Remote",
            local: { LocalConfiguration.forEnvironment($0).data },
            remote: { RemoteConfiguration.forEnvironment($0).data }
        )
    }

    func testStagingLayersRemoteOverLocalOverDefault() async throws {
        let config = makeConfig()
        let pole = FlagPole(AppFlags.self, sources: config.sources)

        await config.load(.staging)

        // Endpoint is set by both layers; the remote value wins.
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")
        XCTAssertEqual(
            pole.resolution(for: "checkout.endpoint", as: .url).sourceName, "Remote"
        )
        // Page size is set by neither layer — the compiled default.
        XCTAssertEqual(pole.pageSize, 10)
        XCTAssertTrue(pole.resolution(for: "page-size", as: .int).isDefault)
    }

    func testClearingRemoteFallsBackToTheLocalLayerNotTheDefault() async throws {
        let config = makeConfig()
        let pole = FlagPole(AppFlags.self, sources: config.sources)
        await config.load(.staging)
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")

        config.remoteSource.clear()

        // The local staging endpoint, not the compiled default — the local layer earning
        // its place.
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging-local.example")
        XCTAssertEqual(
            pole.resolution(for: "checkout.endpoint", as: .url).sourceName, "Local"
        )
    }

    func testSwitchingEnvironmentReplacesBothLayers() async throws {
        let config = makeConfig()
        let pole = FlagPole(AppFlags.self, sources: config.sources)

        await config.load(.staging)
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")

        await config.load(.local)

        // Local environment's remote layer points at localhost; staging is gone.
        XCTAssertEqual(pole.checkout.endpoint.host(), "localhost")
    }
}
