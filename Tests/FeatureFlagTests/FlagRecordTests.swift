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

    func testTheMemberwiseInitialiserSurvivesTheMacro() {
        // The generated initialiser lives in an extension for exactly this reason.
        // Declared among the members it would suppress the one Swift writes, leaving a
        // record nobody can construct — including in the `default:` its flag needs.
        let endpoint = Endpoint(
            name: "adhoc",
            url: URL(string: "https://adhoc.example")!,
            enabled: true,
            weight: 1,
            expires: Date(timeIntervalSince1970: 0),
            tier: .primary
        )

        XCTAssertEqual(endpoint.name, "adhoc")
    }

    func testARecordCanBeWrittenByHandWithoutTheMacro() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(FlagRecords([Note(text: "by hand")]).box, for: "notes")

        let pole = FlagPole(HandWrittenFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.notes.values, [Note(text: "by hand")])
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

    // MARK: - Reading through the shape alone

    func testStoredTextCanBeReadBackFromTheShapeWithoutTheSwiftType() throws {
        // What the companion app does. It has the schema and nothing else.
        let box = FlagRecords([Endpoint.staging, Endpoint.canary]).box

        let records = try XCTUnwrap(box.recordValues(matching: Endpoint.flagRecordShape))

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?["name"], .string("staging"))
        XCTAssertEqual(records.first?["weight"], .int(7))
        XCTAssertEqual(records.last?["tier"], .string("secondary"))
    }

    func testAListWithAnIncompleteRecordCannotBeReadThroughItsShape() {
        // Strict on purpose: the host would reject this list and fall back to its
        // default, so an editor that showed it would be showing a value not in effect.
        let box = FlagValueBox.string("""
            [{"name":"partial","enabled":true}]
            """)

        XCTAssertNil(box.recordValues(matching: Endpoint.flagRecordShape))
    }

    func testRecordsBuiltFromBoxesAloneMatchWhatTheTypeWouldHaveWritten() throws {
        // The companion writes this; the host reads it. They have to agree exactly.
        let built = FlagValueBox.records(
            [Endpoint.canary.flagRecordBoxes, Endpoint.staging.flagRecordBoxes]
        )

        XCTAssertEqual(built, FlagRecords([Endpoint.canary, Endpoint.staging]).box)
    }

    func testAValueThatIsNotEvenTextIsNotRecords() {
        XCTAssertNil(FlagValueBox.int(3).recordValues(matching: Endpoint.flagRecordShape))
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

@FlagRecord
private struct Endpoint {

    var name: String
    var url: URL
    var enabled: Bool
    var weight: Int
    var expires: Date
    var tier: Tier

    static let fieldNames = ["name", "url", "enabled", "weight", "expires", "tier"]
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

/// The macro is the supported path, but the protocol is public and documented as
/// conformable by hand. This is what that costs.
private struct Note: FlagRecord {

    var text: String

    static var flagRecordShape: [FlagRecordField] {
        [FlagRecordField(name: "text", type: String.flagValueType)]
    }

    var flagRecordBoxes: [String: FlagValueBox] { ["text": text.box] }

    init(text: String) {
        self.text = text
    }

    init?(flagRecordBoxes boxes: [String: FlagValueBox]) {
        guard let text = boxes["text"].flatMap(String.init(box:)) else { return nil }
        self.text = text
    }
}

@FlagContainer
private struct HandWrittenFlags {

    @Flag(default: [], description: "Notes")
    var notes: FlagRecords<Note>
}
