import FeatureFlag
import FeatureFlagTestSupport
import XCTest

/// The XCTest wrapper is thin — the audit's own tests carry the logic. These prove it
/// links, passes on a good payload, and is where a real test would live.
final class XCTAssertFlagsFullyMappedTests: XCTestCase {

    func testACompletePayloadPasses() {
        let json = """
            { "featureToggles": { "onboarding": true },
              "config": { "pageSize": 25, "tier": "pro" } }
            """
        XCTAssertFlagsFullyMapped(HelperFlags.self, applying: Data(json.utf8))
    }

    func testStrictWithIgnoredMetadataPasses() {
        // A real config: every flag wired up, plus metadata no flag reads. Strict, but
        // the metadata is excused, so it passes.
        let json = """
            { "featureToggles": { "onboarding": true },
              "config": { "pageSize": 25, "tier": "pro" },
              "meta": { "version": 7 } }
            """
        XCTAssertFlagsFullyMapped(
            HelperFlags.self, applying: Data(json.utf8), strict: true, ignoring: ["meta"]
        )
    }
}

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}

@FlagContainer
private struct HelperFlags {

    @Flag(default: false, description: "Onboarding", remoteKey: "featureToggles.onboarding")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Page size", remoteKey: "config.pageSize")
    var pageSize: Int

    @Flag(default: Tier.free, description: "Tier", remoteKey: "config.tier")
    var checkoutTier: Tier
}
