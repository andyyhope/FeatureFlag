import XCTest

@testable import FeatureFlag

/// Checking, without running an app, that a payload wires up every flag it should — and
/// that every value in the payload is read by something.
///
/// Validation is already strict and all-or-nothing, so the audit never has to check
/// types itself: if a value mapped, it is correct. What it adds is coverage in both
/// directions — a flag whose path found nothing, and a value no flag reads.
final class FlagMappingAuditTests: XCTestCase {

    private let complete = """
        {
          "featureToggles": { "onboarding": true },
          "config": { "pageSize": 25, "tier": "pro" }
        }
        """

    // MARK: - Forward coverage: every flag found its value

    func testACompletePayloadHasNothingAbsentAndIsComplete() throws {
        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(complete.utf8))

        XCTAssertEqual(audit.absent, [])
        XCTAssertEqual(audit.mismatched, [])
        XCTAssertEqual(
            Set(audit.applied), ["new-onboarding", "page-size", "checkout-tier"]
        )
        XCTAssertTrue(audit.isComplete)
    }

    func testATypoInARemoteKeyShowsAsAnAbsentFlag() throws {
        // The whole point: a path that matches nothing is not an error at apply time,
        // so it looks exactly like a backend that sent no value. Here it is named.
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "page_size": 25, "tier": "pro" } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(audit.absent, ["page-size"])
        XCTAssertFalse(audit.isComplete)
    }

    // MARK: - Reverse coverage: every value is read

    func testAValueNoFlagReadsIsListedAsUnconsumed() throws {
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "pageSize": 25, "tier": "pro" },
              "meta": { "version": 7 } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(audit.unconsumed, ["meta.version"])
    }

    func testUnconsumedValuesDoNotFailTheDefaultAudit() throws {
        // A real config carries metadata no flag reads. The default audit reports it
        // without failing, so the tool does not cry wolf.
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "pageSize": 25, "tier": "pro" },
              "meta": { "version": 7 } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertTrue(audit.isComplete)
        XCTAssertFalse(audit.isComplete(strict: true))
        XCTAssertTrue(audit.isComplete(strict: true, ignoring: ["meta"]))
    }

    func testStrictModeCatchesATypoThatLenientCoverageMisses() throws {
        // page_size is both an absent flag AND an unconsumed value — the same typo seen
        // from both directions. Strict mode makes the unconsumed side fail too.
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "page_size": 25, "tier": "pro" } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(audit.absent, ["page-size"])
        XCTAssertEqual(audit.unconsumed, ["config.page_size"])
    }

    // MARK: - A record flag consumes its whole subtree

    func testARecordFlagCoversEveryLeafBeneathItsPath() throws {
        let payload = """
            { "config": { "endpoints": [
                { "name": "a", "url": "https://a.example" },
                { "name": "b", "url": "https://b.example" }
            ] } }
            """

        let audit = try FlagMappingAudit(RecordAuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(audit.unconsumed, [], "the record flag reads the whole list")
        XCTAssertEqual(audit.applied, ["endpoints"])
    }

    // MARK: - Mismatches are collected, not thrown

    func testEveryTypeMismatchIsReportedAtOnce() throws {
        let payload = """
            { "featureToggles": { "onboarding": "yes" },
              "config": { "pageSize": "lots", "tier": "pro" } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(
            Set(audit.mismatched.map(\.key)), ["new-onboarding", "page-size"]
        )
        XCTAssertFalse(audit.isComplete)
    }

    func testAnEnumCaseThisBuildLacksIsAMismatch() throws {
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "pageSize": 25, "tier": "gold" } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertEqual(audit.mismatched.map(\.key), ["checkout-tier"])
        XCTAssertEqual(audit.mismatched.first?.kind, .unknownCase)
    }

    // MARK: - Flags with no remoteKey

    func testAFlagWithNoRemoteKeyIsNeitherAppliedNorAbsent() throws {
        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(complete.utf8))

        XCTAssertEqual(audit.notRemotelyOverridable, ["local-only"])
        XCTAssertFalse(audit.applied.contains("local-only"))
        XCTAssertFalse(audit.absent.contains("local-only"))
    }

    // MARK: - Reporting

    func testTheDescriptionNamesEveryProblem() throws {
        let payload = """
            { "config": { "page_size": 25, "tier": "gold" },
              "meta": { "version": 7 } }
            """

        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))
        let text = audit.description

        XCTAssertTrue(text.contains("new-onboarding"), text)   // absent
        XCTAssertTrue(text.contains("checkout-tier"), text)    // mismatched
        XCTAssertTrue(text.contains("meta.version"), text)     // unconsumed
        XCTAssertFalse(text.contains("FeatureFlag."), text)    // no reflected types
    }

    func testRequireCompleteThrowsWhenIncomplete() throws {
        let payload = """
            { "featureToggles": { "onboarding": true },
              "config": { "page_size": 25, "tier": "pro" } }
            """
        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(payload.utf8))

        XCTAssertThrowsError(try audit.requireComplete())
    }

    func testRequireCompleteIsSilentWhenComplete() throws {
        let audit = try FlagMappingAudit(AuditFlags.self, applying: Data(complete.utf8))

        XCTAssertNoThrow(try audit.requireComplete())
    }

    // MARK: - Bad input

    func testMalformedJSONThrowsRatherThanAuditing() {
        XCTAssertThrowsError(
            try FlagMappingAudit(AuditFlags.self, applying: Data("{ not json".utf8))
        )
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}

@FlagContainer
private struct AuditFlags {

    @Flag(default: false, description: "Onboarding", remoteKey: "featureToggles.onboarding")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Page size", remoteKey: "config.pageSize")
    var pageSize: Int

    @Flag(default: Tier.free, description: "Tier", remoteKey: "config.tier")
    var checkoutTier: Tier

    @Flag(default: "x", description: "Not remotely overridable")
    var localOnly: String
}

@FlagRecord
private struct Endpoint {
    @FlagRecordKey var name: String
    var url: URL
}

@FlagContainer
private struct RecordAuditFlags {

    @Flag(default: [], description: "Endpoints", remoteKey: "config.endpoints")
    var endpoints: FlagRecords<Endpoint>
}
