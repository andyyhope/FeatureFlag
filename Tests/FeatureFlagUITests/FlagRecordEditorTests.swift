import FeatureFlag
import SwiftUI
import XCTest

@testable import FeatureFlagUI

/// Editing a list of records: a row per record, a control per field, and the four
/// verbs a list needs — add, duplicate, reorder, remove.
final class FlagRecordEditorTests: XCTestCase {

    /// Fresh per test method, so each one starts from the compiled defaults.
    private let source = SnapshotSource(name: "shared")

    private func makeStore() -> FlagEditingStore {
        FlagEditingStore(schema: FlagSchema(RecordEditorFlags.self), source: source)
    }

    private func entry(_ store: FlagEditingStore, _ key: FlagKey) throws -> FlagSchema.Entry {
        try XCTUnwrap(store.entry(for: key))
    }

    // MARK: - Which flags get the record editor

    func testARecordFlagGetsTheRecordEditor() throws {
        let store = makeStore()

        XCTAssertEqual(
            try entry(store, "endpoints").editorKind,
            .records(Endpoint.flagRecordShape)
        )
    }

    func testAPlainStringFlagIsStillJustText() throws {
        let store = makeStore()

        XCTAssertEqual(try entry(store, "name").editorKind, .text)
    }

    // MARK: - Reading

    func testTheDefaultRecordsAreReadableBeforeAnythingIsOverridden() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")

        let records = try XCTUnwrap(store.records(for: entry))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["name"], .string("production"))
    }

    func testTextThatIsNotAListOfRecordsReadsAsUnreadableRatherThanEmpty() throws {
        // Empty and unreadable are different: one is a list you emptied, the other is a
        // value the host is already ignoring. Showing "0 items" for the second would
        // invite you to add one and wonder why nothing changed.
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setValue(.string("{ not json"), for: entry)

        XCTAssertNil(store.records(for: entry))
    }

    // MARK: - The four verbs

    func testAddingAppendsARecordOfEmptyFields() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        let records = try XCTUnwrap(store.records(for: entry))

        try store.setRecords(records + [entry.emptyRecord], for: entry)

        let updated = try XCTUnwrap(store.records(for: entry))
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated.last?["name"], .string(""))
        XCTAssertEqual(updated.last?["weight"], .int(0))
    }

    func testANewRecordsEnumFieldStartsOnARealCase() throws {
        // The trap this avoids: an empty string is not a `Tier`, so a record added with
        // one would be rejected by the host the moment it read the list — and the
        // whole flag would quietly fall back to its default.
        let store = makeStore()
        let entry = try entry(store, "endpoints")

        try store.setRecords([entry.emptyRecord], for: entry)

        let pole = FlagPole(RecordEditorFlags.self, sources: [source])
        XCTAssertEqual(pole.flags.endpoints.values.count, 1)
        XCTAssertEqual(pole.flags.endpoints.values.first?.tier, .primary)
    }

    func testDuplicatingPutsTheCopyRightAfterTheOriginal() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setRecords([staging, canary], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records.insert(records[0], at: 1)
        try store.setRecords(records, for: entry)

        let updated = try XCTUnwrap(store.records(for: entry))
        XCTAssertEqual(updated.map { $0["name"] }, [
            .string("staging"), .string("staging"), .string("canary"),
        ])
    }

    func testReorderingIsWrittenBackInTheNewOrder() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setRecords([staging, canary], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        try store.setRecords(records, for: entry)

        let updated = try XCTUnwrap(store.records(for: entry))
        XCTAssertEqual(updated.map { $0["name"] }, [.string("canary"), .string("staging")])
    }

    func testRemovingLeavesTheRest() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setRecords([staging, canary], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records.remove(atOffsets: IndexSet(integer: 0))
        try store.setRecords(records, for: entry)

        XCTAssertEqual(try XCTUnwrap(store.records(for: entry)).map { $0["name"] }, [
            .string("canary")
        ])
    }

    func testEditingOneFieldLeavesEveryOtherRecordAlone() throws {
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setRecords([staging, canary], for: entry)

        var records = try XCTUnwrap(store.records(for: entry))
        records[1]["weight"] = .int(99)
        try store.setRecords(records, for: entry)

        let updated = try XCTUnwrap(store.records(for: entry))
        XCTAssertEqual(updated[0], staging)
        XCTAssertEqual(updated[1]["weight"], .int(99))
        XCTAssertEqual(updated[1]["name"], .string("canary"))
    }

    // MARK: - Writing something the host can read

    func testWhatTheEditorWritesIsWhatTheHostReads() throws {
        // The whole point. The companion has only the shape; the host has the type.
        let store = makeStore()
        let entry = try entry(store, "endpoints")
        try store.setRecords([staging, canary], for: entry)

        let pole = FlagPole(RecordEditorFlags.self, sources: [source])

        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["staging", "canary"])
        XCTAssertEqual(pole.flags.endpoints.values.map(\.weight), [7, 3])
        XCTAssertEqual(pole.flags.endpoints.values.first?.tier, .secondary)
    }

    // MARK: - Fixtures

    private var staging: [String: FlagValueBox] {
        [
            "name": .string("staging"),
            "url": .url(URL(string: "https://staging.example")!),
            "enabled": .bool(false),
            "weight": .int(7),
            "tier": .string("secondary"),
        ]
    }

    private var canary: [String: FlagValueBox] {
        [
            "name": .string("canary"),
            "url": .url(URL(string: "https://canary.example")!),
            "enabled": .bool(true),
            "weight": .int(3),
            "tier": .string("primary"),
        ]
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
    var tier: Tier
}

@FlagContainer
private struct RecordEditorFlags {

    @Flag(
        default: [
            Endpoint(
                name: "production",
                url: URL(string: "https://prod.example")!,
                enabled: true,
                weight: 10,
                tier: .primary
            )
        ],
        description: "Endpoints"
    )
    var endpoints: FlagRecords<Endpoint>

    @Flag(default: "Demo", description: "Name")
    var name: String
}
