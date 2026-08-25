import XCTest

@testable import FeatureFlag

/// Alongside coverage, the audit shows how a config's values compare to the compiled
/// defaults: which flags it actually changes, and which it merely restates.
///
/// This never affects `isComplete` — a value equal to its default is not a coverage
/// problem, and neither is one that differs. It is a diff, for you to read.
final class FlagDefaultDiffTests: XCTestCase {

    private func audit(_ json: String) throws -> FlagMappingAudit {
        try FlagMappingAudit(DiffFlags.self, applying: Data(json.utf8))
    }

    // MARK: - The split

    func testAValueEqualToTheDefaultIsAMatch() throws {
        let audit = try audit("""
            { "featureToggles": { "onboarding": false },
              "config": { "pageSize": 99 } }
            """)

        XCTAssertEqual(audit.matchesDefault, ["new-onboarding"])   // default false, sent false
        XCTAssertEqual(audit.changesDefault, ["page-size"])        // default 10, sent 99
    }

    func testEveryComparisonCarriesBothValues() throws {
        let audit = try audit("""
            { "config": { "pageSize": 99 } }
            """)
        let diff = try XCTUnwrap(audit.defaults.first { $0.key == "page-size" })

        XCTAssertEqual(diff.defaultValue, .int(10))
        XCTAssertEqual(diff.incomingValue, .int(99))
        XCTAssertFalse(diff.matchesDefault)
    }

    func testOnlyFlagsTheConfigSuppliedAppearInTheDiff() throws {
        // A flag the payload never mentions has no incoming value to compare.
        let audit = try audit("""
            { "config": { "pageSize": 99 } }
            """)

        XCTAssertEqual(audit.defaults.map(\.key), ["page-size"])
        XCTAssertFalse(audit.defaults.contains { $0.key == "new-onboarding" })
    }

    // MARK: - Independence from completeness

    func testAValueMatchingTheDefaultDoesNotFailTheAudit() throws {
        // Every remote flag supplied, every value equal to its default.
        let audit = try audit("""
            { "featureToggles": { "onboarding": false },
              "config": { "pageSize": 10, "ratio": 3.0 } }
            """)

        XCTAssertEqual(audit.matchesDefault, ["new-onboarding", "page-size", "ratio"])
        XCTAssertEqual(audit.changesDefault, [])
        XCTAssertTrue(audit.isComplete, "restating a default is not a coverage failure")
    }

    // MARK: - Number widening

    func testAWholeNumberSentForADoubleStillMatchesADoubleDefault() throws {
        // JSON has one number type: 3 for a Double flag defaulting to 3.0 is the same
        // value, not a change.
        let audit = try audit("""
            { "config": { "ratio": 3 } }
            """)

        XCTAssertEqual(audit.matchesDefault, ["ratio"])
    }

    // MARK: - Records

    func testARecordListRestatedExactlyMatchesItsDefault() throws {
        let audit = try FlagMappingAudit(
            RecordDiffFlags.self,
            applying: Data(#"{"config":{"endpoints":[{"name":"a","url":"https://a.example"}]}}"#.utf8)
        )

        XCTAssertEqual(audit.matchesDefault, ["endpoints"])
    }

    func testRecordFieldOrderInTheConfigDoesNotCreateAFalseChange() throws {
        // url before name — a different textual order than the default's boxing. Both
        // canonicalise to sorted keys, so it is the same value, not a change.
        let audit = try FlagMappingAudit(
            RecordDiffFlags.self,
            applying: Data(#"{"config":{"endpoints":[{"url":"https://a.example","name":"a"}]}}"#.utf8)
        )

        XCTAssertEqual(audit.changesDefault, [])
    }

    // MARK: - Reporting

    func testTheDiffDescriptionShowsChangesAndMatches() throws {
        let audit = try audit("""
            { "featureToggles": { "onboarding": false },
              "config": { "pageSize": 99 } }
            """)
        let text = audit.defaultsDescription

        XCTAssertTrue(text.contains("page-size"), text)
        XCTAssertTrue(text.contains("10"), text)
        XCTAssertTrue(text.contains("99"), text)
        XCTAssertFalse(text.contains("FeatureFlag."), text)
    }

    func testTheDiffOfAConfigThatChangesNothingSaysSo() throws {
        let audit = try audit("{}")

        XCTAssertEqual(audit.defaults, [])
        XCTAssertTrue(audit.defaultsDescription.contains("nothing"), audit.defaultsDescription)
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Endpoint {
    @FlagRecordKey var name: String
    var url: URL
}

@FlagContainer
private struct RecordDiffFlags {

    @Flag(
        default: [Endpoint(name: "a", url: URL(string: "https://a.example")!)],
        description: "Endpoints",
        remoteKey: "config.endpoints"
    )
    var endpoints: FlagRecords<Endpoint>
}

@FlagContainer
private struct DiffFlags {

    @Flag(default: false, description: "Onboarding", remoteKey: "featureToggles.onboarding")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Page size", remoteKey: "config.pageSize")
    var pageSize: Int

    @Flag(default: 3.0, description: "Ratio", remoteKey: "config.ratio")
    var ratio: Double
}
