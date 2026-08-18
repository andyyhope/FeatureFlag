import XCTest

@testable import FeatureFlag

/// Adding a field to a record used to invalidate every list already stored: the app
/// fell back to its compiled default and any override set before the change stopped
/// taking effect, silently.
///
/// A field written with an initialiser carries that value into the shape, so a record
/// stored before the field existed can be filled rather than rejected — which is what
/// Swift's own memberwise initialiser does with the same syntax.
final class FlagRecordDefaultTests: XCTestCase {

    // MARK: - What the shape carries

    func testAFieldWrittenWithAnInitialiserPublishesItAsItsDefault() throws {
        let shape = Endpoint.flagRecordShape

        let weight = try XCTUnwrap(shape.first { $0.name == "weight" })
        XCTAssertEqual(weight.defaultValue, .int(1))

        let region = try XCTUnwrap(shape.first { $0.name == "region" })
        XCTAssertEqual(region.defaultValue, .string("au"))
    }

    func testAFieldWithoutAnInitialiserHasNoDefault() throws {
        let name = try XCTUnwrap(Endpoint.flagRecordShape.first { $0.name == "name" })

        XCTAssertNil(name.defaultValue)
    }

    // MARK: - Reading a list written before the field existed

    func testAStoredRecordMissingADefaultedFieldIsFilledRatherThanRejected() throws {
        // Written by a build whose Endpoint had only `name` and `url`.
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("""
            [{"name":"legacy","url":"https://legacy.example"}]
            """), for: "endpoints")

        let pole = FlagPole(DefaultedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["legacy"])
        XCTAssertEqual(pole.flags.endpoints.values.first?.weight, 1)
        XCTAssertEqual(pole.flags.endpoints.values.first?.region, "au")
    }

    func testAStoredRecordMissingAFieldWithNoDefaultIsStillRejected() throws {
        // `name` has nothing to fall back to, so the list is still all or nothing.
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("""
            [{"url":"https://nameless.example"}]
            """), for: "endpoints")

        let pole = FlagPole(DefaultedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["production"])
    }

    func testAFieldThatIsPresentButWrongIsStillRejectedEvenWithADefault() throws {
        // Filling in an absent field is a migration; overwriting a wrong one would be
        // guessing, and would hide a payload that genuinely disagrees with the app.
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("""
            [{"name":"bad","url":"https://x.example","weight":"heavy"}]
            """), for: "endpoints")

        let pole = FlagPole(DefaultedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["production"])
    }

    // MARK: - Everywhere else that reads records

    func testTheShapeAloneFillsDefaultsToo() throws {
        // What the companion uses; it must agree with the host exactly.
        let box = FlagValueBox.string("""
            [{"name":"legacy","url":"https://legacy.example"}]
            """)

        let records = try XCTUnwrap(box.recordValues(matching: Endpoint.flagRecordShape))

        XCTAssertEqual(records.first?["weight"], .int(1))
        XCTAssertEqual(records.first?["region"], .string("au"))
    }

    func testARemotePayloadMayOmitADefaultedField() throws {
        let remote = RemoteOverrideSource(DefaultedFlags.self)
        try remote.apply(Data("""
            { "config": { "endpoints": [
                { "name": "from-backend", "url": "https://backend.example" }
            ] } }
            """.utf8), format: .json)

        let pole = FlagPole(DefaultedFlags.self, sources: [remote])

        XCTAssertEqual(pole.flags.endpoints.values.first?.weight, 1)
    }

    func testARemotePayloadStillCannotOmitAFieldWithNoDefault() {
        let remote = RemoteOverrideSource(DefaultedFlags.self)

        XCTAssertThrowsError(
            try remote.apply(Data("""
                { "config": { "endpoints": [ { "url": "https://backend.example" } ] } }
                """.utf8), format: .json)
        )
    }

    func testTheSchemaCarriesDefaultsToTheCompanion() throws {
        let schema = FlagSchema(DefaultedFlags.self)
        let reread = try FlagSchema(jsonData: schema.jsonData())
        let entry = try XCTUnwrap(reread.flags.first { $0.key == "endpoints" })

        XCTAssertEqual(
            entry.recordShape?.first { $0.name == "weight" }?.defaultValue,
            .int(1)
        )
        XCTAssertNil(entry.recordShape?.first { $0.name == "name" }?.defaultValue)
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Endpoint {
    var name: String
    var url: URL
    var weight: Int = 1
    var region: String = "au"
}

@FlagContainer
private struct DefaultedFlags {

    @Flag(
        default: [
            Endpoint(name: "production", url: URL(string: "https://prod.example")!)
        ],
        description: "Endpoints",
        remoteKey: "config.endpoints"
    )
    var endpoints: FlagRecords<Endpoint>
}
