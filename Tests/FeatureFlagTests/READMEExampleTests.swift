import Combine
import XCTest

import FeatureFlag

/// Every code sample in README.md, compiled and run.
///
/// A README that has drifted from the API is worse than no README, and nothing else in
/// the suite would notice. Change a sample here and change it there.
final class READMEExampleTests: XCTestCase {

    /// The quick-start declaration and read.
    func testQuickStartCompilesAndReads() throws {
        let local = SnapshotSource(name: "local")
        let flags = FlagPole(AppFlags.self, sources: [local, RemoteOverrideSource(AppFlags.self)])

        XCTAssertFalse(flags.checkout.applePay)

        try local.setBox(.bool(true), for: "checkout.apple-pay")
        XCTAssertTrue(flags.checkout.applePay)
    }

    /// The precedence sample: `resolution(for:)` naming the winning source.
    func testResolutionSampleNamesTheSource() throws {
        let local = SnapshotSource(name: "App Group")
        let flags = FlagPole(AppFlags.self, sources: [local])

        XCTAssertNil(flags.resolution(for: flags.flags.$newOnboarding).sourceName)

        try local.setBox(.bool(true), for: "new-onboarding")
        XCTAssertEqual(flags.resolution(for: flags.flags.$newOnboarding).sourceName, "App Group")
    }

    /// The remote overrides sample, minus the URLSession call the framework never makes.
    func testRemoteOverrideSampleApplies() throws {
        let remote = RemoteOverrideSource(AppFlags.self)
        let flags = FlagPole(AppFlags.self, sources: [remote])

        let data = Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8)
        try remote.apply(data, format: .json)

        XCTAssertTrue(flags.newOnboarding)
    }

    /// The claim that a bad field rejects the whole payload and reports everything.
    func testRemoteValidationIsStrictAsDocumented() throws {
        let remote = RemoteOverrideSource(AppFlags.self)
        let flags = FlagPole(AppFlags.self, sources: [remote])

        let data = Data(#"{"featureToggles": {"onboarding": {"v2": "true"}}}"#.utf8)
        XCTAssertThrowsError(try remote.apply(data, format: .json))
        XCTAssertFalse(flags.newOnboarding)
    }

    /// The claim that a whole number satisfies a Double flag but `"true"` is not a Bool,
    /// checked the way a reader would meet it: through a payload.
    func testDocumentedNumberAllowance() throws {
        let remote = RemoteOverrideSource(NumberAllowanceFlags.self)
        let flags = FlagPole(NumberAllowanceFlags.self, sources: [remote])

        try remote.apply(Data(#"{"cfg": {"ratio": 1}}"#.utf8), format: .json)
        XCTAssertEqual(flags.ratio, 1.0, "a whole number should satisfy a Double flag")

        XCTAssertThrowsError(
            try remote.apply(Data(#"{"cfg": {"enabled": "true"}}"#.utf8), format: .json),
            "a quoted true is still not a boolean"
        )
    }

    /// The schema publishing sample.
    func testPublishSchemaSampleWritesSomethingReadable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let flags = FlagPole(AppFlags.self, sources: [])
        try flags.publishSchema(inDirectory: directory)

        let loaded = try FlagSchema(contentsOfDirectory: directory)
        XCTAssertEqual(loaded.flags.map(\.key), ["new-onboarding", "checkout.apple-pay", "checkout.tier"])
    }

    /// The claim that an enum publishes its cases, which is what earns it a picker.
    func testEnumPublishesItsCases() throws {
        let schema = FlagPole(AppFlags.self, sources: []).schema
        let tier = try XCTUnwrap(schema.flags.first { $0.key == "checkout.tier" })
        XCTAssertEqual(tier.cases, [.string("free"), .string("pro")])
    }

    /// The records sample: the declaration, and the stored form the README describes.
    func testRecordsSampleCompilesAndStoresAsJSONText() {
        let flags = FlagPole(READMERecordFlags.self, sources: [])

        XCTAssertEqual(flags.paymentMethods.values.map(\.name), ["Visa"])
        XCTAssertEqual(
            flags.$paymentMethods.defaultValue.box,
            .string(#"[{"enabled":true,"kind":"card","name":"Visa"}]"#)
        )
    }

    /// "Adding a field to a record invalidates lists already stored."
    func testRecordsSampleFallsBackWhenAStoredListPredatesAField() throws {
        let local = SnapshotSource(name: "local")
        // Written by a build whose PaymentMethod had no `enabled`.
        try local.setBox(.string(#"[{"kind":"card","name":"Amex"}]"#), for: "payment-methods")

        let flags = FlagPole(READMERecordFlags.self, sources: [local])

        XCTAssertEqual(flags.paymentMethods.values.map(\.name), ["Visa"])
    }

    /// The dynamic member lookup caveat: real members win.
    func testDocumentedShadowingCaveatHolds() {
        let flags = FlagPole(AppFlags.self, sources: [])
        XCTAssertTrue(type(of: flags.keys) == [FlagKey].self)
        XCTAssertEqual(flags.keys.count, 3)
    }
}

// MARK: - Exactly as written in README.md

@FlagContainer
private struct AppFlags {

    @Flag(
        default: false,
        description: "Show the redesigned onboarding",
        remoteKey: "featureToggles.onboarding.v2"
    )
    var newOnboarding: Bool

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

@FlagContainer
private struct CheckoutFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool

    @Flag(default: Tier.free, description: "Pricing tier to present")
    var tier: Tier
}

private enum PaymentKind: String, FlagValue, CaseIterable, FlagValueCases {
    case card, wallet
}

@FlagRecord
private struct PaymentMethod {
    var name: String
    var kind: PaymentKind
    var enabled: Bool
}

@FlagContainer
private struct READMERecordFlags {

    @Flag(
        default: [PaymentMethod(name: "Visa", kind: .card, enabled: true)],
        description: "Payment methods offered at checkout"
    )
    var paymentMethods: FlagRecords<PaymentMethod>
}

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}

@FlagContainer
private struct NumberAllowanceFlags {

    @Flag(default: 0.0, description: "Ratio", remoteKey: "cfg.ratio")
    var ratio: Double

    @Flag(default: false, description: "Enabled", remoteKey: "cfg.enabled")
    var enabled: Bool
}
