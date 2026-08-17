import XCTest

@testable import FeatureFlag

/// Records — a flag holding a list of fixed-shape values, each field typed.
///
/// The conformance below is written by hand on purpose. It is exactly what
/// `@FlagRecord` generates, so writing it out first is how we find out whether the
/// generated code is something a person could have written.
final class FlagRecordTests: XCTestCase {

    // MARK: - Round trips

    func testAListOfRecordsRoundTripsThroughASource() throws {
        let local = SnapshotSource(name: "local")
        let edited = FlagRecords([Endpoint.staging, Endpoint.canary])
        try local.setBox(edited.box, for: "endpoints")

        let pole = FlagPole(RecordFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values, [.staging, .canary])
    }

    func testTheCompiledDefaultIsUsedWhenNothingOverrides() {
        let pole = FlagPole(RecordFlags.self, sources: [])

        XCTAssertEqual(pole.flags.endpoints.values, [.production])
    }

    func testAnEmptyListIsAValueLikeAnyOther() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(FlagRecords<Endpoint>([]).box, for: "endpoints")

        let pole = FlagPole(RecordFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values, [])
    }

    // MARK: - Wire format

    func testDatesAndURLsAreWrittenTheWayEveryOtherFlagWritesThem() throws {
        // The reason records box field by field rather than going through Codable:
        // JSONEncoder writes a Date as a number by default, so a date inside a record
        // would have been serialised differently from a date in a flag beside it.
        guard case let .string(json) = FlagRecords([Endpoint.production]).box else {
            return XCTFail("a record list boxes as a string")
        }

        XCTAssertTrue(
            json.contains("\"expires\":\"2023-11-14T22:13:20Z\""),
            "expected an ISO 8601 date, got \(json)"
        )
        XCTAssertTrue(json.contains("\"url\":\"https://prod.example\""), json)
    }

    func testTheStoredFormIsPlainJSONAnybodyCouldRead() throws {
        guard case let .string(json) = FlagRecords([Endpoint.canary]).box else {
            return XCTFail("a record list boxes as a string")
        }
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]

        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(parsed?.first?["name"] as? String, "canary")
        XCTAssertEqual(parsed?.first?["enabled"] as? Bool, true)
        XCTAssertEqual(parsed?.first?["weight"] as? Int, 3)
        XCTAssertEqual(parsed?.first?["tier"] as? String, "secondary")
    }

    // MARK: - Degrading

    func testStoredTextThatIsNotJSONFallsBackToTheDefault() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("{ not json"), for: "endpoints")

        let pole = FlagPole(RecordFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values, [.production])
    }

    func testARecordMissingAFieldFallsBackToTheDefault() throws {
        // An older host's record, read by a build that has since added a field. The
        // whole list degrades rather than yielding a half-built value.
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("""
            [{"name":"partial","enabled":true}]
            """), for: "endpoints")

        let pole = FlagPole(RecordFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values, [.production])
    }

    func testAFieldOfTheWrongTypeFallsBackToTheDefault() throws {
        func endpoints(withEnabled enabled: String) throws -> [Endpoint] {
            let local = SnapshotSource(name: "local")
            try local.setBox(.string("""
                [{"name":"bad","url":"https://x.example","enabled":\(enabled),"weight":1,\
                "expires":"2023-11-14T22:13:20Z","tier":"primary"}]
                """), for: "endpoints")
            return FlagPole(RecordFlags.self, sources: [local]).flags.endpoints.values
        }

        // The control. Without it this test would pass just as happily if some other
        // field were the one being rejected.
        XCTAssertEqual(try endpoints(withEnabled: "true").map(\.name), ["bad"])

        XCTAssertEqual(try endpoints(withEnabled: "\"yes\""), [.production])
    }

    // MARK: - Schema

    func testTheSchemaCarriesTheShapeSoACompanionCanRenderIt() throws {
        let schema = FlagSchema(RecordFlags.self)
        let entry = try XCTUnwrap(schema.flags.first { $0.key == "endpoints" })

        XCTAssertEqual(entry.recordShape?.map(\.name), Endpoint.fieldNames)
        XCTAssertEqual(
            entry.recordShape?.map(\.type),
            [.string, .url, .bool, .int, .date, .string]
        )
    }

    func testAnEnumFieldPublishesItsCasesSoTheEditorCanShowAPicker() throws {
        let schema = FlagSchema(RecordFlags.self)
        let entry = try XCTUnwrap(schema.flags.first { $0.key == "endpoints" })
        let tier = try XCTUnwrap(entry.recordShape?.first { $0.name == "tier" })

        XCTAssertEqual(tier.cases, [.string("primary"), .string("secondary")])
    }

    func testAFieldWithNoCasesSaysSoRatherThanSayingNone() throws {
        let schema = FlagSchema(RecordFlags.self)
        let entry = try XCTUnwrap(schema.flags.first { $0.key == "endpoints" })
        let name = try XCTUnwrap(entry.recordShape?.first { $0.name == "name" })

        XCTAssertNil(name.cases)
    }

    func testTheShapeSurvivesTheDocumentACompanionActuallyReads() throws {
        let schema = FlagSchema(RecordFlags.self)

        let reread = try FlagSchema(jsonData: schema.jsonData())
        let entry = try XCTUnwrap(reread.flags.first { $0.key == "endpoints" })

        XCTAssertEqual(entry.recordShape, schema.flags.first { $0.key == "endpoints" }?.recordShape)
    }

    func testARecordFlagIsAStringToAnybodyWhoDoesNotKnowBetter() throws {
        // What buys the graceful degradation: an older companion reads `valueType`
        // and finds a name it already understands, so the rest of the document still
        // renders. An unrecognised type name would have rejected the whole schema.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try FlagSchema(RecordFlags.self).jsonData())
                as? [String: Any]
        )
        let flags = try XCTUnwrap(object["flags"] as? [[String: Any]])
        let entry = try XCTUnwrap(flags.first { $0["key"] as? String == "endpoints" })

        XCTAssertEqual(entry["valueType"] as? String, "string")
    }

    func testADocumentWithoutAShapeStillDecodes() throws {
        // Every schema published before records existed.
        let json = """
            {
              "formatVersion": 1,
              "generatedAt": "2026-01-01T00:00:00.000Z",
              "flags": [
                { "key": "greeting", "propertyPath": ["greeting"], "description": "Hi",
                  "valueType": "string", "defaultValue": "hello" }
              ],
              "groups": []
            }
            """

        let schema = try FlagSchema(jsonData: Data(json.utf8))

        XCTAssertNil(schema.flags.first?.recordShape)
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, FlagValueCases, CaseIterable {
    case primary
    case secondary
}

/// Hand-written for now; `@FlagRecord` generates exactly this in phase two.
private struct Endpoint: FlagRecord {

    var name: String
    var url: URL
    var enabled: Bool
    var weight: Int
    var expires: Date
    var tier: Tier

    static let fieldNames = ["name", "url", "enabled", "weight", "expires", "tier"]

    static var flagRecordShape: [FlagRecordField] {
        [
            FlagRecordField(name: "name", type: String.flagValueType, cases: _flagValueCases(of: String.self)),
            FlagRecordField(name: "url", type: URL.flagValueType, cases: _flagValueCases(of: URL.self)),
            FlagRecordField(name: "enabled", type: Bool.flagValueType, cases: _flagValueCases(of: Bool.self)),
            FlagRecordField(name: "weight", type: Int.flagValueType, cases: _flagValueCases(of: Int.self)),
            FlagRecordField(name: "expires", type: Date.flagValueType, cases: _flagValueCases(of: Date.self)),
            FlagRecordField(name: "tier", type: Tier.flagValueType, cases: _flagValueCases(of: Tier.self)),
        ]
    }

    var flagRecordBoxes: [String: FlagValueBox] {
        [
            "name": name.box,
            "url": url.box,
            "enabled": enabled.box,
            "weight": weight.box,
            "expires": expires.box,
            "tier": tier.box,
        ]
    }

    init?(flagRecordBoxes boxes: [String: FlagValueBox]) {
        guard
            let name = boxes["name"].flatMap(String.init(box:)),
            let url = boxes["url"].flatMap(URL.init(box:)),
            let enabled = boxes["enabled"].flatMap(Bool.init(box:)),
            let weight = boxes["weight"].flatMap(Int.init(box:)),
            let expires = boxes["expires"].flatMap(Date.init(box:)),
            let tier = boxes["tier"].flatMap(Tier.init(box:))
        else { return nil }

        self.init(name: name, url: url, enabled: enabled, weight: weight, expires: expires, tier: tier)
    }

    init(name: String, url: URL, enabled: Bool, weight: Int, expires: Date, tier: Tier) {
        self.name = name
        self.url = url
        self.enabled = enabled
        self.weight = weight
        self.expires = expires
        self.tier = tier
    }
}

extension Endpoint {

    private static let expiry = Date(timeIntervalSince1970: 1_700_000_000)

    static let production = Endpoint(
        name: "production", url: URL(string: "https://prod.example")!,
        enabled: true, weight: 10, expires: expiry, tier: .primary
    )

    static let staging = Endpoint(
        name: "staging", url: URL(string: "https://staging.example")!,
        enabled: false, weight: 7, expires: expiry, tier: .secondary
    )

    static let canary = Endpoint(
        name: "canary", url: URL(string: "https://canary.example")!,
        enabled: true, weight: 3, expires: expiry, tier: .secondary
    )
}

@FlagContainer
private struct RecordFlags {

    @Flag(default: [Endpoint.production], description: "Endpoints")
    var endpoints: FlagRecords<Endpoint>
}
