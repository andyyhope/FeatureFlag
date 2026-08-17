import FeatureFlag
import XCTest

@testable import DemoExamples

/// The demo's bundled payloads are hand-written JSON addressed by dot path. A typo in a
/// path fails silently as "the backend sent nothing", which is exactly the bug the demo
/// exists to make visible — so the payloads themselves need checking.
final class RemoteConfigurationTests: XCTestCase {

    private func makePole() -> (FlagPole<AppFlags>, RemoteOverrideSource, SnapshotSource) {
        let local = SnapshotSource(name: "Companion")
        let remote = RemoteOverrideSource(AppFlags.self, name: "Remote")
        return (FlagPole(AppFlags.self, sources: [local, remote]), remote, local)
    }

    private var allConfigurations: [RemoteConfiguration] {
        DemoEnvironment.allCases.map(RemoteConfiguration.forEnvironment) + [.malformed]
    }

    func testEveryBundledPayloadIsValidJSON() throws {
        for configuration in allConfigurations {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: configuration.data),
                "\(configuration.name) is not valid JSON"
            )
        }
    }

    func testStagingReachesEveryFlagItClaimsTo() throws {
        let (pole, remote, _) = makePole()
        let result = try remote.apply(RemoteConfiguration.staging.data, format: .json)

        // If a dot path were wrong the key would land in absentKeys instead.
        XCTAssertTrue(result.absentKeys.isEmpty, "unmatched paths: \(result.absentKeys)")
        XCTAssertEqual(
            result.appliedKeys,
            ["checkout.apple-pay", "checkout.endpoint", "new-onboarding", "payment-methods"]
        )

        XCTAssertTrue(pole.newOnboarding)
        XCTAssertTrue(pole.checkout.applePay)
        XCTAssertEqual(pole.checkout.endpoint.host(), "staging.api.example.com")
    }

    // MARK: - Records

    func testAPayloadReplacesTheWholeListOfRecords() throws {
        let (pole, remote, _) = makePole()
        XCTAssertEqual(pole.paymentMethods.values.count, 3, "the compiled default")

        try remote.apply(RemoteConfiguration.local.data, format: .json)

        XCTAssertEqual(pole.paymentMethods.values.map(\.name), ["Test card"])
        XCTAssertEqual(pole.paymentMethods.values.first?.kind, .card)
    }

    func testEachEnvironmentBringsItsOwnPaymentMethods() throws {
        let (pole, remote, _) = makePole()

        try remote.apply(RemoteConfiguration.production.data, format: .json)
        XCTAssertEqual(pole.paymentMethods.values.map(\.name), ["Visa", "Mastercard"])

        try remote.apply(RemoteConfiguration.staging.data, format: .json)
        XCTAssertEqual(
            pole.paymentMethods.values.map(\.name),
            ["Visa", "Apple Pay", "Bank transfer"]
        )
        XCTAssertEqual(pole.paymentMethods.values.last?.minimumSpend, 10)
    }

    func testEveryBundledPayloadSendsRecordsThisBuildCanRead() throws {
        // A payload naming a payment kind the app has never heard of, or missing a
        // field, would reject the whole thing — including the flags beside it.
        for configuration in [
            RemoteConfiguration.production, .staging, .local,
        ] {
            let (_, remote, _) = makePole()
            XCTAssertNoThrow(
                try remote.apply(configuration.data, format: .json),
                "\(configuration.name) was rejected"
            )
        }
    }

    func testProductionTurnsThingsOff() throws {
        let (pole, remote, _) = makePole()
        try remote.apply(RemoteConfiguration.staging.data, format: .json)
        XCTAssertTrue(pole.checkout.applePay)

        let result = try remote.apply(RemoteConfiguration.production.data, format: .json)
        XCTAssertTrue(result.absentKeys.isEmpty)
        XCTAssertFalse(pole.checkout.applePay)
        XCTAssertFalse(pole.newOnboarding)
    }

    func testTheMalformedPayloadIsRejectedAndAppliesNothing() throws {
        let (pole, remote, _) = makePole()

        XCTAssertThrowsError(
            try remote.apply(RemoteConfiguration.malformed.data, format: .json)
        ) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.typeMismatch])
            XCTAssertEqual(problems.map(\.remoteKey), ["featureToggles.onboarding.v2"])
        }

        // The payload also carried a valid applePay: it must not have been applied.
        XCTAssertFalse(pole.checkout.applePay, "all-or-nothing means nothing")
    }

    func testOnlyTheMalformedPayloadIsLabelledBroken() {
        XCTAssertTrue(RemoteConfiguration.malformed.isDeliberatelyBroken)
        for environment in DemoEnvironment.allCases {
            XCTAssertFalse(RemoteConfiguration.forEnvironment(environment).isDeliberatelyBroken)
        }
    }

    /// The demo's headline claim, and the reason for the source ordering.
    func testACompanionOverrideSurvivesARemotePayload() throws {
        let (pole, remote, local) = makePole()

        try local.setBox(.bool(true), for: "checkout.apple-pay")
        try remote.apply(RemoteConfiguration.production.data, format: .json)

        XCTAssertTrue(pole.checkout.applePay, "a hand-set override outranks the backend")
        XCTAssertEqual(
            pole.resolution(for: "checkout.apple-pay", as: .bool).sourceName,
            "Companion"
        )

        // Clear it and the backend's value shows through.
        try local.setBox(nil, for: "checkout.apple-pay")
        XCTAssertFalse(pole.checkout.applePay)
        XCTAssertEqual(
            pole.resolution(for: "checkout.apple-pay", as: .bool).sourceName,
            "Remote"
        )
    }
}
