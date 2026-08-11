import Combine
import FeatureFlag
import XCTest

@testable import FeatureFlagUI

final class FlagEditingStoreEdgeCaseTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Sections

    func testASchemaWithNoGroupsIsOneUnnamedSection() {
        let store = FlagEditingStore(
            schema: FlagSchema(flags: [entry(key: "a"), entry(key: "b")]),
            source: SnapshotSource(name: "local")
        )
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertNil(store.sections[0].title)
        XCTAssertEqual(store.sections[0].entries.count, 2)
    }

    func testAnEmptySchemaHasNoSections() {
        let store = FlagEditingStore(
            schema: FlagSchema(flags: []),
            source: SnapshotSource(name: "local")
        )
        XCTAssertTrue(store.sections.isEmpty)
    }

    func testAGroupHoldingOnlyOtherGroupsShowsNoEmptySection() {
        // "Checkout" contains nothing directly, so it would render as a blank heading.
        let store = FlagEditingStore(
            schema: FlagSchema(
                flags: [entry(key: "checkout.express.one-tap", path: ["checkout", "express", "oneTap"])],
                groups: [
                    FlagSchema.Group(propertyPath: ["checkout"], description: "Checkout"),
                    FlagSchema.Group(propertyPath: ["checkout", "express"], description: "Express"),
                ]
            ),
            source: SnapshotSource(name: "local")
        )
        XCTAssertEqual(store.sections.map(\.title), ["Express"])
        XCTAssertEqual(store.sections[0].pathDescription, "Checkout › Express")
    }

    func testSearchingForSomethingAbsentLeavesNoSections() {
        let store = makeStore()
        store.searchText = "zzzz"
        XCTAssertTrue(store.sections.isEmpty)
    }

    func testSearchIgnoresSurroundingWhitespace() {
        let store = makeStore()
        store.searchText = "   apple   "
        XCTAssertEqual(store.sections.flatMap(\.entries).map(\.key), ["checkout.apple-pay"])
    }

    // MARK: - Overrides

    func testResettingEverythingLeavesForeignKeysAlone() throws {
        // A companion app shares the App Group suite with whatever else lives there.
        let source = SnapshotSource(name: "local")
        try source.setBox(.string("someone else's"), for: "unrelated.key")
        let store = FlagEditingStore(schema: FlagSchema(DemoUIFlags.self), source: source)

        try store.setValue(.bool(true), for: XCTUnwrap(store.entry(for: "new-onboarding")))
        try store.resetAll()

        XCTAssertTrue(store.overriddenKeys.isEmpty)
        XCTAssertEqual(source.values["unrelated.key"], .string("someone else's"))
    }

    func testAStoredValueOfTheWrongTypeReadsAsNotOverridden() throws {
        // A hand-edited or stale suite should show the default, not a broken control.
        let source = SnapshotSource(name: "local")
        let store = FlagEditingStore(schema: FlagSchema(DemoUIFlags.self), source: source)
        let entry = try XCTUnwrap(store.entry(for: "max-items"))

        try source.setBox(.string("nonsense"), for: "max-items")

        XCTAssertEqual(store.value(for: entry), .int(10))
        XCTAssertFalse(store.isOverridden(entry))
    }

    func testAStoredValueOutsideAnEnumsCasesReadsAsNotOverridden() throws {
        // The host cannot represent it either, so it falls back to the default. The
        // editor must agree, or it shows a picker with nothing selected.
        let source = SnapshotSource(name: "local")
        let schema = FlagSchema(
            flags: [
                FlagSchema.Entry(
                    key: "tier",
                    propertyPath: ["tier"],
                    description: "Tier",
                    valueType: .string,
                    defaultValue: .string("free"),
                    cases: [.string("free"), .string("pro")]
                )
            ]
        )
        let store = FlagEditingStore(schema: schema, source: source)
        let entry = try XCTUnwrap(store.entry(for: "tier"))

        try source.setBox(.string("enterprise"), for: "tier")

        XCTAssertEqual(store.value(for: entry), .string("free"))
        XCTAssertFalse(store.isOverridden(entry))

        try source.setBox(.string("pro"), for: "tier")
        XCTAssertTrue(store.isOverridden(entry))
    }

    func testEntryLookupForAnUnknownKeyReturnsNothing() {
        XCTAssertNil(makeStore().entry(for: "not-a-flag"))
    }

    // MARK: - Live updates

    func testAnEditFromAnotherProcessRefreshesTheEditor() {
        // Stands in for the host app, or a second companion, writing to the shared suite.
        let source = SnapshotSource(name: "shared")
        let store = FlagEditingStore(schema: FlagSchema(DemoUIFlags.self), source: source)

        let changed = expectation(description: "objectWillChange")
        store.objectWillChange.sink { _ in changed.fulfill() }.store(in: &cancellables)

        try? source.setBox(.bool(true), for: "new-onboarding")
        wait(for: [changed], timeout: 2)
    }

    // MARK: - Import

    func testImportingSomethingForeignIsRejectedWithEveryProblem() {
        let store = makeStore()
        let json = #"{"formatVersion":1,"values":{"nope":1,"max-items":"lots"}}"#

        XCTAssertThrowsError(try store.import(Data(json.utf8), as: .json)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(Set(problems.map(\.key)), ["nope", "max-items"])
        }
        XCTAssertTrue(store.overriddenKeys.isEmpty)
    }

    func testImportingAQRCodeThatIsNotOneIsRejected() {
        XCTAssertThrowsError(try makeStore().importQRCode("hello")) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .unrecognisedFormat)
        }
    }

    func testExportingNothingStillProducesAValidDocument() throws {
        let store = makeStore()
        let data = try store.export(as: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(object["values"] as? [String: Any]).count, 0)
    }

    // MARK: - Helpers

    private func makeStore() -> FlagEditingStore {
        FlagEditingStore(schema: FlagSchema(DemoUIFlags.self), source: SnapshotSource(name: "local"))
    }

    private func entry(key: FlagKey, path: [String]? = nil) -> FlagSchema.Entry {
        FlagSchema.Entry(
            key: key,
            propertyPath: path ?? [key.rawValue],
            description: "",
            valueType: .bool,
            defaultValue: .bool(false)
        )
    }
}

// MARK: - Fixtures

@FlagContainer
private struct DemoUIFlags {

    @Flag(default: false, description: "New onboarding")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Maximum items")
    var maxItems: Int

    @FlagGroup(description: "Checkout")
    var checkout: DemoUICheckoutFlags
}

@FlagContainer
private struct DemoUICheckoutFlags {

    @Flag(default: false, description: "Apple Pay")
    var applePay: Bool
}
