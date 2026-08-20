import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// The companion cannot write a list the host will refuse, so a key it enforces has to
/// be enforced here too — including by "Add", which would otherwise make two records
/// sharing an empty key the moment you pressed it twice.
final class FlagRecordKeyEditorTests: XCTestCase {

    private let source = SnapshotSource(name: "shared")

    private func makeStore() -> FlagEditingStore {
        FlagEditingStore(schema: FlagSchema(KeyedEditorFlags.self), source: source)
    }

    private func entry(_ store: FlagEditingStore) throws -> FlagSchema.Entry {
        try XCTUnwrap(store.entry(for: "routes"))
    }

    func testAddingTwiceMakesTwoRecordsTheHostCanRead() throws {
        let store = makeStore()
        let entry = try entry(store)

        try store.setRecords([entry.emptyRecord], for: entry)
        var records = try XCTUnwrap(store.records(for: entry))
        records.append(entry.emptyRecord(alongside: records))
        try store.setRecords(records, for: entry)

        let pole = FlagPole(KeyedEditorFlags.self, sources: [source])
        XCTAssertEqual(pole.flags.routes.values.count, 2, "the host refused the list")
        XCTAssertEqual(
            Set(pole.flags.routes.values.map(\.name)).count, 2, "both records share a name"
        )
    }

    func testAThirdAddIsStillDistinct() throws {
        let store = makeStore()
        let entry = try entry(store)

        var records: [[String: FlagValueBox]] = []
        for _ in 0..<3 {
            records.append(entry.emptyRecord(alongside: records))
        }
        try store.setRecords(records, for: entry)

        let pole = FlagPole(KeyedEditorFlags.self, sources: [source])
        XCTAssertEqual(pole.flags.routes.values.count, 3)
    }

    func testAnEditThatWouldCollideIsRefused() throws {
        let store = makeStore()
        let entry = try entry(store)
        try store.setRecords([named("a"), named("b")], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records[1]["name"] = .string("a")

        XCTAssertThrowsError(try store.setRecords(records, for: entry))
        XCTAssertEqual(
            try XCTUnwrap(store.records(for: entry)).map { $0["name"] },
            [.string("a"), .string("b")],
            "the refused write should have changed nothing"
        )
    }

    func testAnEditThatDoesNotCollideIsAccepted() throws {
        let store = makeStore()
        let entry = try entry(store)
        try store.setRecords([named("a"), named("b")], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records[1]["name"] = .string("c")

        XCTAssertNoThrow(try store.setRecords(records, for: entry))
    }

    func testARecordWithNoKeyIsUnaffected() throws {
        let store = makeStore()
        let notes = try XCTUnwrap(store.entry(for: "notes"))

        XCTAssertNoThrow(
            try store.setRecords([["text": .string("same")], ["text": .string("same")]], for: notes)
        )
    }

    func testAListWithADuplicateKeyReadsAsUnreadableToTheEditorToo() throws {
        // The host refuses it, so the editor must agree — and must say which rule was
        // broken, since a duplicate key is a well-formed list failing a different one.
        let store = makeStore()
        let entry = try entry(store)
        try store.setValue(
            .string(#"[{"name":"a","hops":"[]"},{"name":"a","hops":"[]"}]"#),
            for: entry
        )

        XCTAssertNil(store.records(for: entry))
        XCTAssertEqual(
            store.value(for: entry).duplicateRecordKey(matching: try XCTUnwrap(entry.recordShape)),
            .string("a")
        )
    }

    private func named(_ name: String) -> [String: FlagValueBox] {
        ["name": .string(name), "hops": .string("[]")]
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Hop {
    var host: String
}

@FlagRecord
private struct Route {
    @FlagRecordKey var name: String
    var hops: FlagRecords<Hop> = []
}

@FlagRecord
private struct EditorNote {
    var text: String
}

@FlagContainer
private struct KeyedEditorFlags {

    @Flag(default: [], description: "Routes")
    var routes: FlagRecords<Route>

    @Flag(default: [], description: "Notes")
    var notes: FlagRecords<EditorNote>
}
