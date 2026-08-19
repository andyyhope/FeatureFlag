import XCTest

@testable import FeatureFlag

final class FlagPayloadTests: XCTestCase {

    private func makeTower() -> FlagPole<DemoFlags> {
        FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])
    }

    // MARK: - Export

    func testExportCarriesOnlyOverriddenFlags() throws {
        let tower = makeTower()
        try tower.setOverride(true, for: tower.flags.$newOnboarding)

        let payload = tower.exportPayload()
        XCTAssertEqual(payload.values, ["new-onboarding": .bool(true)])
    }

    func testExportOfAnUntouchedTowerIsEmpty() {
        XCTAssertTrue(makeTower().exportPayload().values.isEmpty)
    }

    func testExportedJSONIsFlatAndHandEditable() throws {
        let tower = makeTower()
        try tower.setOverride(true, for: tower.flags.$newOnboarding)
        try tower.setOverride(3, for: tower.flags.$maxItems)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try tower.export(as: .json)) as? [String: Any]
        )
        let values = try XCTUnwrap(object["values"] as? [String: Any])

        XCTAssertEqual(values["new-onboarding"] as? Bool, true)
        XCTAssertEqual(values["max-items"] as? Int, 3)
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
    }

    func testDatesDataAndURLsExportAsPlainStrings() throws {
        // No "$type" wrappers: the schema already says what each key is, so the JSON
        // stays something a person can read and edit.
        let tower = FlagPole(TransportFlags.self, sources: [SnapshotSource(name: "local")])
        try tower.setOverride(Date(timeIntervalSince1970: 0), for: tower.flags.$launchedAt)
        try tower.setOverride(URL(string: "https://example.com")!, for: tower.flags.$endpoint)
        try tower.setOverride(Data([0x01, 0x02]), for: tower.flags.$blob)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try tower.export(as: .json)) as? [String: Any]
        )
        let values = try XCTUnwrap(object["values"] as? [String: Any])

        XCTAssertEqual(values["launched-at"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(values["endpoint"] as? String, "https://example.com")
        XCTAssertEqual(values["blob"] as? String, "AQI=")
    }

    // MARK: - Round trips

    func testJSONRoundTripsEveryOverride() throws {
        let source = FlagPole(TransportFlags.self, sources: [SnapshotSource(name: "local")])
        try source.setOverride(Date(timeIntervalSince1970: 1_000), for: source.flags.$launchedAt)
        try source.setOverride(URL(string: "https://example.com/a?b=c")!, for: source.flags.$endpoint)
        try source.setOverride(Data([0x01, 0xFF]), for: source.flags.$blob)
        try source.setOverride(["x", "y"], for: source.flags.$tags)
        try source.setOverride(["a": 1], for: source.flags.$limits)
        try source.setOverride(2.5 as Float, for: source.flags.$ratio)

        let destination = FlagPole(
            TransportFlags.self, sources: [SnapshotSource(name: "local")]
        )
        _ = try destination.importPayload(try source.export(as: .json), as: .json)

        XCTAssertEqual(destination.overrides, source.overrides)
    }

    func testPLISTRoundTripsEveryOverride() throws {
        let source = FlagPole(TransportFlags.self, sources: [SnapshotSource(name: "local")])
        try source.setOverride(Date(timeIntervalSince1970: 1_000), for: source.flags.$launchedAt)
        try source.setOverride(Data([0x01, 0xFF]), for: source.flags.$blob)
        try source.setOverride(["x"], for: source.flags.$tags)

        let destination = FlagPole(
            TransportFlags.self, sources: [SnapshotSource(name: "local")]
        )
        _ = try destination.importPayload(try source.export(as: .plist), as: .plist)

        XCTAssertEqual(destination.overrides, source.overrides)
    }

    func testEnumOverridesRoundTrip() throws {
        let source = makeTower()
        try source.setOverride(DemoTier.pro, for: source.flags.checkout.$tier)

        let destination = makeTower()
        _ = try destination.importPayload(try source.export(as: .json), as: .json)

        XCTAssertEqual(destination.flags.checkout.tier, .pro)
    }

    // MARK: - Import is strict and all-or-nothing

    func testImportReportsWhatItApplied() throws {
        let source = makeTower()
        try source.setOverride(true, for: source.flags.$newOnboarding)
        try source.setOverride(3, for: source.flags.$maxItems)

        let destination = makeTower()
        let result = try destination.importPayload(try source.export(as: .json), as: .json)

        XCTAssertEqual(result.appliedKeys.sorted { $0.rawValue < $1.rawValue }, ["max-items", "new-onboarding"])
    }

    func testImportRejectsAnUnknownKeyAndAppliesNothing() throws {
        let json = """
            {"formatVersion": 1, "values": {"new-onboarding": true, "not-a-flag": 1}}
            """
        let tower = makeTower()

        XCTAssertThrowsError(try tower.importPayload(Data(json.utf8), as: .json)) { error in
            XCTAssertEqual(
                error as? FlagImportError,
                .rejected([
                    FlagImportProblem(key: "not-a-flag", kind: .unknownKey, found: "1")
                ])
            )
        }
        XCTAssertFalse(tower.flags.newOnboarding)
    }

    func testImportRejectsAMistypedValueAndAppliesNothing() throws {
        let json = """
            {"formatVersion": 1, "values": {"new-onboarding": true, "max-items": "lots"}}
            """
        let tower = makeTower()

        XCTAssertThrowsError(try tower.importPayload(Data(json.utf8), as: .json)) { error in
            XCTAssertEqual(
                error as? FlagImportError,
                .rejected([
                    FlagImportProblem(
                        key: "max-items",
                        kind: .typeMismatch,
                        expected: "int",
                        found: "\"lots\""
                    )
                ])
            )
        }
        XCTAssertFalse(tower.flags.newOnboarding)
    }

    func testImportReportsEveryProblemAtOnce() throws {
        let json = """
            {"formatVersion": 1, "values": {"not-a-flag": 1, "max-items": "lots"}}
            """
        let tower = makeTower()

        XCTAssertThrowsError(try tower.importPayload(Data(json.utf8), as: .json)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected")
            }
            XCTAssertEqual(
                Set(problems),
                [
                    FlagImportProblem(key: "not-a-flag", kind: .unknownKey, found: "1"),
                    FlagImportProblem(
                        key: "max-items",
                        kind: .typeMismatch,
                        expected: "int",
                        found: "\"lots\""
                    ),
                ]
            )
        }
    }

    func testImportRejectsAnUnknownFormatVersion() {
        let json = #"{"formatVersion": 99, "values": {}}"#
        XCTAssertThrowsError(try makeTower().importPayload(Data(json.utf8), as: .json)) { error in
            XCTAssertEqual(error as? FlagImportError, .unsupportedFormatVersion(99))
        }
    }

    func testImportRejectsMalformedData() {
        XCTAssertThrowsError(try makeTower().importPayload(Data("not json".utf8), as: .json)) {
            error in
            guard case .malformed = error as? FlagImportError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }
}

// MARK: - Fixtures

@FlagContainer
private struct TransportFlags {

    @Flag(default: Date(timeIntervalSince1970: 0), description: "Launched at")
    var launchedAt: Date

    @Flag(default: URL(string: "https://default.example")!, description: "Endpoint")
    var endpoint: URL

    @Flag(default: Data(), description: "Blob")
    var blob: Data

    @Flag(default: [], description: "Tags")
    var tags: [String]

    @Flag(default: [:], description: "Limits")
    var limits: [String: Int]

    @Flag(default: 1.0, description: "Ratio")
    var ratio: Float
}
