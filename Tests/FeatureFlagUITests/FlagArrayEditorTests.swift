import FeatureFlag
import SwiftUI
import XCTest

@testable import FeatureFlagUI

/// Editing an array a row at a time, rather than as a block of JSON where a misplaced
/// comma rejects the whole value.
final class FlagArrayEditorTests: XCTestCase {

    private func makeStore() -> FlagEditingStore {
        FlagEditingStore(
            schema: FlagSchema(ArrayEditorFlags.self),
            source: SnapshotSource(name: "shared")
        )
    }

    private func entry(_ store: FlagEditingStore, _ key: FlagKey) throws -> FlagSchema.Entry {
        try XCTUnwrap(store.entry(for: key))
    }

    // MARK: - Which flags get the list editor

    func testAnArrayOfScalarsGetsAListEditor() throws {
        let store = makeStore()
        XCTAssertEqual(try entry(store, "markets").editorKind, .list(element: .string))
        XCTAssertEqual(try entry(store, "counts").editorKind, .list(element: .int))
        XCTAssertEqual(try entry(store, "launches").editorKind, .list(element: .date))
    }

    /// An array of arrays has no row that reads well, and a dictionary has no order.
    func testStructuralValuesStayAsJSON() throws {
        let store = makeStore()
        XCTAssertEqual(try entry(store, "nested").editorKind, .json)
        XCTAssertEqual(try entry(store, "shares").editorKind, .json)
    }

    func testScalarsAreUnaffected() throws {
        let store = makeStore()
        XCTAssertEqual(try entry(store, "name").editorKind, .text)
    }

    // MARK: - Adding, changing, removing

    func testAddingAppendsAnEmptyElementOfTheRightType() throws {
        let store = makeStore()
        let entry = try entry(store, "markets")

        try store.setValue(.array([.string("AU")]), for: entry)
        try store.setValue(.array([.string("AU"), FlagValueType.string.emptyBox]), for: entry)

        XCTAssertEqual(store.value(for: entry), .array([.string("AU"), .string("")]))
    }

    func testEveryTypeHasSomethingToAdd() {
        XCTAssertEqual(FlagValueType.bool.emptyBox, .bool(false))
        XCTAssertEqual(FlagValueType.int.emptyBox, .int(0))
        XCTAssertEqual(FlagValueType.double.emptyBox, .double(0))
        XCTAssertEqual(FlagValueType.string.emptyBox, .string(""))
        XCTAssertEqual(FlagValueType.data.emptyBox, .data(Data()))
        XCTAssertEqual(FlagValueType.array(.int).emptyBox, .array([.int(0)]))
        XCTAssertEqual(FlagValueType.dictionary(.int).emptyBox, .dictionary([:]))
        // A URL has no empty form that is still a URL, so it gets a placeholder.
        XCTAssertNotNil(FlagValueType.url.emptyBox)
    }

    func testEditingAnElementWritesTheWholeArrayBack() throws {
        let store = makeStore()
        let entry = try entry(store, "counts")

        try store.setValue(.array([.int(1), .int(2), .int(3)]), for: entry)
        var values: [FlagValueBox] = [.int(1), .int(2), .int(3)]
        values[1] = .int(20)
        try store.setValue(.array(values), for: entry)

        XCTAssertEqual(store.value(for: entry), .array([.int(1), .int(20), .int(3)]))
    }

    /// Removing every element leaves an empty array, which is a value — not the same as
    /// having no override at all.
    func testAnEmptyArrayIsStillAnOverride() throws {
        let store = makeStore()
        let entry = try entry(store, "markets")

        try store.setValue(.array([]), for: entry)

        XCTAssertTrue(store.isOverridden(entry))
        XCTAssertEqual(store.value(for: entry), .array([]))

        try store.reset(entry)
        XCTAssertFalse(store.isOverridden(entry))
        XCTAssertEqual(store.value(for: entry), .array([.string("AU"), .string("NZ")]))
    }

    // MARK: - Elements round-trip through their text

    /// The row edits text and commits a box, so every scalar has to survive the trip.
    func testEachElementTypeSurvivesItsDisplayString() {
        let cases: [(FlagValueType, FlagValueBox)] = [
            (.string, .string("AU")),
            (.int, .int(-3)),
            (.double, .double(2.5)),
            (.float, .float(1.5)),
            (.url, .url(URL(string: "https://a.example/x")!)),
            (.data, .data(Data([0x01, 0x02]))),
        ]

        for (type, box) in cases {
            XCTAssertEqual(
                FlagValueBox(displayString: box.displayString, as: type),
                box,
                "\(type) should survive its display string"
            )
        }
    }

    func testAnUneditableElementIsRejectedRatherThanStored() {
        XCTAssertNil(FlagValueBox(displayString: "not a number", as: .int))
        XCTAssertNil(FlagValueBox(displayString: "", as: .url))
    }

    // MARK: - The views build

    func testTheEditorBuilds() throws {
        let store = makeStore()
        let view = FlagArrayEditorView(
            store: store, entry: try entry(store, "markets"), element: .string
        )
        XCTAssertNotNil(view.body)
    }

    func testAnElementRowBuildsForEveryScalar() {
        for element in [FlagValueType.string, .int, .double, .bool, .date, .url, .data] {
            let row = FlagArrayElementRow(
                value: element.emptyBox, element: element, onChange: { _ in }
            )
            XCTAssertNotNil(row.body, "\(element) should have a row")
        }
    }

    func testTheFlagRowStillBuildsForAnArray() throws {
        let store = makeStore()
        XCTAssertNotNil(FlagRowView(store: store, entry: try entry(store, "markets")).body)
    }
}

@FlagContainer
private struct ArrayEditorFlags {

    @Flag(default: ["AU", "NZ"], description: "Markets")
    var markets: [String]

    @Flag(default: [1, 2], description: "Counts")
    var counts: [Int]

    @Flag(default: [], description: "Launch dates")
    var launches: [Date]

    @Flag(default: [["a"]], description: "Nested")
    var nested: [[String]]

    @Flag(default: [:], description: "Shares")
    var shares: [String: Double]

    @Flag(default: "demo", description: "Name")
    var name: String
}
