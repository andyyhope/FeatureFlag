import XCTest

@testable import FeatureFlag

/// A record whose field is itself a list of records.
///
/// This already round-tripped — `FlagRecords` is a `FlagValue`, so it boxed as a string
/// inside its parent's JSON — but the shape described it as a plain string, so the
/// companion showed a block of escaped JSON and a backend had to send one.
final class FlagNestedRecordTests: XCTestCase {

    // MARK: - The shape

    func testANestedListDescribesItsOwnFields() throws {
        let targets = try XCTUnwrap(Cluster.flagRecordShape.first { $0.name == "targets" })

        XCTAssertEqual(targets.fields?.map(\.name), ["host", "port"])
        XCTAssertEqual(targets.fields?.map(\.type), [.string, .int])
    }

    func testAnOrdinaryFieldHasNoNestedFields() throws {
        let name = try XCTUnwrap(Cluster.flagRecordShape.first { $0.name == "name" })

        XCTAssertNil(name.fields)
    }

    func testTheNestedShapeSurvivesTheDocumentTheCompanionReads() throws {
        let schema = FlagSchema(NestedFlags.self)

        let reread = try FlagSchema(jsonData: schema.jsonData())
        let entry = try XCTUnwrap(reread.flags.first { $0.key == "clusters" })
        let targets = try XCTUnwrap(entry.recordShape?.first { $0.name == "targets" })

        XCTAssertEqual(targets.fields?.map(\.name), ["host", "port"])
    }

    // MARK: - Reading and writing

    func testANestedListRoundTripsThroughTheStore() throws {
        let local = SnapshotSource(name: "local")
        let value = FlagRecords([
            Cluster(name: "ap", targets: [Target(host: "a", port: 1), Target(host: "b", port: 2)])
        ])
        try local.setBox(value.box, for: "clusters")

        let pole = FlagPole(NestedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.clusters.values.first?.targets.values.map(\.host), ["a", "b"])
    }

    func testANestedListCanBeReadFromItsFieldBoxWithTheShapeAlone() throws {
        // What the companion needs to render a nested editor rather than JSON.
        let cluster = Cluster(name: "ap", targets: [Target(host: "a", port: 1)])
        let boxes = cluster.flagRecordBoxes
        let targets = try XCTUnwrap(Cluster.flagRecordShape.first { $0.name == "targets" })

        let nested = try XCTUnwrap(
            boxes["targets"]?.recordValues(matching: try XCTUnwrap(targets.fields))
        )

        XCTAssertEqual(nested.first?["host"], .string("a"))
        XCTAssertEqual(nested.first?["port"], .int(1))
    }

    // MARK: - From a backend

    func testABackendMaySendANestedListAsRealJSONRatherThanAsAString() throws {
        // The shape it would write anyway. Before this, a nested list had to arrive as
        // a string containing JSON, which no backend produces on purpose.
        let remote = RemoteOverrideSource(NestedFlags.self)
        try remote.apply(Data("""
            { "config": { "clusters": [
                { "name": "ap", "targets": [
                    { "host": "a.example", "port": 443 },
                    { "host": "b.example", "port": 8443 }
                ] }
            ] } }
            """.utf8), format: .json)

        let pole = FlagPole(NestedFlags.self, sources: [remote])

        XCTAssertEqual(pole.flags.clusters.values.first?.name, "ap")
        XCTAssertEqual(
            pole.flags.clusters.values.first?.targets.values.map(\.host),
            ["a.example", "b.example"]
        )
    }

    func testAWrongFieldInsideANestedRecordRejectsTheWholePayload() {
        let remote = RemoteOverrideSource(NestedFlags.self)

        XCTAssertThrowsError(
            try remote.apply(Data("""
                { "config": { "clusters": [
                    { "name": "ap", "targets": [ { "host": "a", "port": "https" } ] }
                ] } }
                """.utf8), format: .json)
        )
    }

    func testANestedListMayStillArriveAsAString() throws {
        // A companion exports it this way, and an export has to import.
        let remote = RemoteOverrideSource(NestedFlags.self)
        try remote.apply(Data("""
            { "config": { "clusters": [
                { "name": "ap", "targets": "[{\\"host\\":\\"a\\",\\"port\\":1}]" }
            ] } }
            """.utf8), format: .json)

        let pole = FlagPole(NestedFlags.self, sources: [remote])

        XCTAssertEqual(pole.flags.clusters.values.first?.targets.values.map(\.host), ["a"])
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Target {
    var host: String
    var port: Int
}

@FlagRecord
private struct Cluster {
    var name: String
    var targets: FlagRecords<Target>
}

@FlagContainer
private struct NestedFlags {

    @Flag(default: [], description: "Clusters", remoteKey: "config.clusters")
    var clusters: FlagRecords<Cluster>
}
