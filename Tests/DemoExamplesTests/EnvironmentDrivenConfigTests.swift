import FeatureFlag
import XCTest

@testable import DemoExamples

/// Playing out "the environment flag drives which remote config gets applied".
final class EnvironmentDrivenConfigTests: XCTestCase {

    private func makePole() -> (FlagPole<AppFlags>, RemoteOverrideSource, SnapshotSource) {
        let local = SnapshotSource(name: "Companion")
        let remote = RemoteOverrideSource(AppFlags.self, name: "Remote")
        return (FlagPole(AppFlags.self, sources: [local, remote]), remote, local)
    }

    /// The invariant the whole arrangement rests on.
    ///
    /// If the environment flag were remotely overridable, a staging payload could set
    /// the environment to production, which would mean a different payload should have
    /// been fetched — and applying that one could set it back. Nothing in the framework
    /// prevents wiring that loop; the absent remoteKey does.
    func testTheEnvironmentFlagIsNotRemotelyOverridable() throws {
        let schema = FlagSchema(AppFlags.self)
        let environment = try XCTUnwrap(schema.flags.first { $0.key == "environment" })

        XCTAssertNil(
            environment.remoteKey,
            "giving environment a remoteKey lets a payload choose which payload gets fetched"
        )
    }

    func testAPayloadCannotChangeTheEnvironmentEvenIfItTries() throws {
        let (pole, remote, _) = makePole()
        let hostile = Data(
            #"{"environment": "staging", "featureToggles": {"onboarding": {"v2": true}}}"#.utf8
        )

        try remote.apply(hostile, format: .json)

        XCTAssertEqual(pole.environment, .production, "the backend does not get a vote")
        XCTAssertTrue(pole.newOnboarding, "the rest of the payload still applies")
    }

    // MARK: - Each environment reaches its own payload

    func testEveryEnvironmentHasAPayloadThatMatchesEveryFlagItClaims() throws {
        for environment in DemoEnvironment.allCases {
            let (_, remote, _) = makePole()
            let configuration = RemoteConfiguration.forEnvironment(environment)
            let result = try remote.apply(configuration.data, format: .json)

            XCTAssertTrue(
                result.absentKeys.isEmpty,
                "\(environment.rawValue): unmatched dot paths \(result.absentKeys)"
            )
        }
    }

    func testSwitchingEnvironmentSwitchesTheBackend() throws {
        let (pole, remote, local) = makePole()

        try remote.apply(RemoteConfiguration.forEnvironment(.production).data, format: .json)
        XCTAssertEqual(pole.checkout.endpoint.host(), "api.example.com")
        XCTAssertFalse(pole.checkout.applePay)

        try local.setBox(.string("staging"), for: "environment")
        try remote.apply(RemoteConfiguration.forEnvironment(pole.environment).data, format: .json)

        XCTAssertEqual(pole.environment, .staging)
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")
        XCTAssertTrue(pole.checkout.applePay)
    }

    /// Clearing before applying leaves a window on compiled defaults. That is the point:
    /// an app labelled "staging" still running production's values would look fine and
    /// be wrong.
    func testClearingFirstFallsBackToDefaultsRatherThanStaleValues() throws {
        let (pole, remote, _) = makePole()

        try remote.apply(RemoteConfiguration.forEnvironment(.staging).data, format: .json)
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")

        remote.clear()

        XCTAssertEqual(
            pole.checkout.endpoint.host(),
            "api.example.com",
            "should be the compiled default, not staging's leftover value"
        )
        XCTAssertTrue(pole.resolution(for: "checkout.endpoint", as: .url).isDefault)
    }

    // MARK: - Precedence still holds

    func testAnOverrideSurvivesAnEnvironmentSwitch() throws {
        // Someone testing Apple Pay does not want it wiped by changing environment.
        let (pole, remote, local) = makePole()
        try local.setBox(.bool(true), for: "checkout.apple-pay")

        try remote.apply(RemoteConfiguration.forEnvironment(.production).data, format: .json)
        XCTAssertTrue(pole.checkout.applePay)
        XCTAssertEqual(pole.resolution(for: "checkout.apple-pay", as: .bool).sourceName, "Companion")

        try local.setBox(nil, for: "checkout.apple-pay")
        XCTAssertFalse(pole.checkout.applePay, "production's value shows through once cleared")
    }
}
