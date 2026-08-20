import XCTest

@testable import FeatureFlag

/// A record can name one field as its key: the thing that tells one record from
/// another. Two records sharing one is a mistake with no correct behaviour, the same
/// as two flags sharing a key or two signal groups sharing a raw value.
final class FlagRecordKeyTests: XCTestCase {

    // MARK: - What the shape carries

    func testTheKeyFieldIsMarkedInTheShape() throws {
        let name = try XCTUnwrap(Endpoint.flagRecordShape.first { $0.name == "name" })
        let url = try XCTUnwrap(Endpoint.flagRecordShape.first { $0.name == "url" })

        XCTAssertTrue(name.isKey)
        XCTAssertFalse(url.isKey)
    }

    func testARecordWithoutAKeyMarksNothing() {
        XCTAssertTrue(Note.flagRecordShape.allSatisfy { $0.isKey == false })
    }

    func testTheKeySurvivesTheDocumentTheCompanionReads() throws {
        let schema = FlagSchema(KeyedFlags.self)

        let reread = try FlagSchema(jsonData: schema.jsonData())
        let entry = try XCTUnwrap(reread.flags.first { $0.key == "endpoints" })

        XCTAssertEqual(entry.recordShape?.first { $0.isKey }?.name, "name")
    }

    // MARK: - Looking one up

    func testARecordCanBeFoundByItsKey() {
        let records = FlagRecords([Endpoint.staging, Endpoint.canary])

        XCTAssertEqual(records["canary"]?.url.host(), "canary.example")
        XCTAssertNil(records["nothing-like-that"])
    }

    func testLookupOnARecordWithNoKeyFindsNothing() {
        let notes = FlagRecords([Note(text: "a")])

        XCTAssertNil(notes["a"])
    }

    // MARK: - Two records sharing a key

    func testAStoredListWithADuplicateKeyFallsBackToTheDefault() throws {
        // Unreadable rather than "first wins": picking one silently would mean the app
        // running on a value nobody chose.
        let local = SnapshotSource(name: "local")
        try local.setBox(.string("""
            [{"name":"staging","url":"https://one.example"},\
            {"name":"staging","url":"https://two.example"}]
            """), for: "endpoints")

        let pole = FlagPole(KeyedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["production"])
    }

    func testTheShapeAloneRefusesADuplicateToo() {
        // What the companion uses; it has to agree with the host exactly.
        let box = FlagValueBox.string("""
            [{"name":"a","url":"https://one.example"},{"name":"a","url":"https://two.example"}]
            """)

        XCTAssertNil(box.recordValues(matching: Endpoint.flagRecordShape))
    }

    func testDistinctKeysAreFine() throws {
        let box = FlagValueBox.string("""
            [{"name":"a","url":"https://one.example"},{"name":"b","url":"https://two.example"}]
            """)

        XCTAssertEqual(box.recordValues(matching: Endpoint.flagRecordShape)?.count, 2)
    }

    func testARecordWithNoKeyAllowsIdenticalRecords() throws {
        // Without a key there is nothing to collide: two identical notes are two notes.
        let box = FlagValueBox.string(#"[{"text":"same"},{"text":"same"}]"#)

        XCTAssertEqual(box.recordValues(matching: Note.flagRecordShape)?.count, 2)
    }

    // MARK: - From a backend

    func testARemotePayloadWithADuplicateKeyIsRejectedAndSaysSo() {
        let remote = RemoteOverrideSource(KeyedFlags.self)

        XCTAssertThrowsError(
            try remote.apply(Data("""
                { "config": { "endpoints": [
                    { "name": "staging", "url": "https://one.example" },
                    { "name": "staging", "url": "https://two.example" }
                ] } }
                """.utf8), format: .json)
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("its own name"), message)
            XCTAssertTrue(message.contains("two with \"staging\""), message)
        }
    }

    func testAnImportedDocumentWithADuplicateKeyIsRejected() {
        let pole = FlagPole(KeyedFlags.self, sources: [SnapshotSource(name: "l")])
        let document = """
            {"formatVersion":1,"values":{"endpoints":"[{\\"name\\":\\"a\\",\\"url\\":\\"https://one.example\\"},\
            {\\"name\\":\\"a\\",\\"url\\":\\"https://two.example\\"}]"}}
            """

        XCTAssertThrowsError(try pole.importPayload(Data(document.utf8), as: .json)) { error in
            XCTAssertTrue(String(describing: error).contains("its own name"), "\(error)")
        }
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Endpoint {
    @FlagRecordKey var name: String
    var url: URL
}

@FlagRecord
private struct Note {
    var text: String
}

extension Endpoint {
    static let staging = Endpoint(name: "staging", url: URL(string: "https://staging.example")!)
    static let canary = Endpoint(name: "canary", url: URL(string: "https://canary.example")!)
}

@FlagContainer
private struct KeyedFlags {

    @Flag(
        default: [Endpoint(name: "production", url: URL(string: "https://prod.example")!)],
        description: "Endpoints",
        remoteKey: "config.endpoints"
    )
    var endpoints: FlagRecords<Endpoint>

    @Flag(default: [], description: "Notes")
    var notes: FlagRecords<Note>
}
