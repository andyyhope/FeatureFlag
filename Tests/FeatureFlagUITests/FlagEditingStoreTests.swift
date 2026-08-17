import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// The companion app never sees the host's Swift types — it works entirely from a
/// published schema and a shared store. Everything here is driven by that pair.
final class FlagEditingStoreTests: XCTestCase {

    private var source: SnapshotSource!
    private var store: FlagEditingStore!

    override func setUp() {
        super.setUp()
        source = SnapshotSource(name: "local")
        store = FlagEditingStore(schema: FlagSchema(CompanionFlags.self), source: source)
    }

    // MARK: - Sections

    func testUngroupedFlagsComeFirstInAnUnnamedSection() {
        let section = store.sections[0]
        XCTAssertNil(section.title)
        XCTAssertEqual(section.entries.map(\.key), ["new-onboarding", "max-items"])
    }

    func testEachGroupBecomesASectionLabelledByItsDescription() {
        XCTAssertEqual(store.sections.map(\.title), [nil, "Checkout", "Express"])
    }

    func testNestedGroupSectionsAreLabelledWithTheirFullPath() {
        XCTAssertEqual(store.sections[2].pathDescription, "Checkout › Express")
    }

    // MARK: - Search

    func testSearchMatchesKeys() {
        store.searchText = "apple"
        XCTAssertEqual(store.sections.flatMap(\.entries).map(\.key), ["checkout.apple-pay"])
    }

    func testSearchMatchesDescriptions() {
        store.searchText = "onboarding"
        XCTAssertEqual(store.sections.flatMap(\.entries).map(\.key), ["new-onboarding"])
    }

    func testSearchIsCaseInsensitive() {
        store.searchText = "APPLE"
        XCTAssertEqual(store.sections.flatMap(\.entries).count, 1)
    }

    func testEmptySectionsAreDroppedWhileSearching() {
        store.searchText = "apple"
        XCTAssertEqual(store.sections.map(\.title), ["Checkout"])
    }

    // MARK: - Values

    func testAFlagWithNoOverrideShowsItsDefault() throws {
        let entry = try XCTUnwrap(store.entry(for: "max-items"))
        XCTAssertEqual(store.value(for: entry), .int(10))
        XCTAssertFalse(store.isOverridden(entry))
    }

    func testSettingAValueMarksTheFlagAsOverridden() throws {
        let entry = try XCTUnwrap(store.entry(for: "max-items"))
        try store.setValue(.int(3), for: entry)

        XCTAssertEqual(store.value(for: entry), .int(3))
        XCTAssertTrue(store.isOverridden(entry))
    }

    func testResettingRestoresTheDefault() throws {
        let entry = try XCTUnwrap(store.entry(for: "max-items"))
        try store.setValue(.int(3), for: entry)
        try store.reset(entry)

        XCTAssertEqual(store.value(for: entry), .int(10))
        XCTAssertFalse(store.isOverridden(entry))
    }

    func testResetAllClearsEveryOverride() throws {
        try store.setValue(.int(3), for: XCTUnwrap(store.entry(for: "max-items")))
        try store.setValue(.bool(true), for: XCTUnwrap(store.entry(for: "new-onboarding")))
        try store.resetAll()

        XCTAssertTrue(store.overriddenKeys.isEmpty)
    }

    func testOverriddenKeysReportsWhatHasBeenChanged() throws {
        try store.setValue(.int(3), for: XCTUnwrap(store.entry(for: "max-items")))
        XCTAssertEqual(store.overriddenKeys, ["max-items"])
    }

    // MARK: - Choosing an editor

    func testEachTypeGetsASuitableEditor() throws {
        func kind(_ key: FlagKey) throws -> FlagEditorKind {
            try XCTUnwrap(store.entry(for: key)).editorKind
        }

        XCTAssertEqual(try kind("new-onboarding"), .toggle)
        XCTAssertEqual(try kind("max-items"), .integer)
        XCTAssertEqual(try kind("checkout.ratio"), .decimal)
        XCTAssertEqual(try kind("checkout.express.label"), .text)
        XCTAssertEqual(try kind("checkout.launched-at"), .date)
        XCTAssertEqual(try kind("checkout.endpoint"), .url)
        XCTAssertEqual(try kind("checkout.express.tags"), .list(element: .string))
    }

    func testAnEnumGetsAPickerOfItsCases() throws {
        let entry = try XCTUnwrap(store.entry(for: "checkout.tier"))
        XCTAssertEqual(entry.editorKind, .picker([.string("free"), .string("pro")]))
    }

    // MARK: - Text editing

    func testValuesRenderAsEditableText() {
        XCTAssertEqual(FlagValueBox.int(3).displayString, "3")
        XCTAssertEqual(FlagValueBox.string("hi").displayString, "hi")
        XCTAssertEqual(FlagValueBox.url(URL(string: "https://a.example")!).displayString, "https://a.example")
        XCTAssertEqual(FlagValueBox.array([.string("a"), .string("b")]).displayString, #"["a","b"]"#)
    }

    func testEditedTextIsParsedBackAccordingToTheDeclaredType() {
        XCTAssertEqual(FlagValueBox(displayString: "3", as: .int), .int(3))
        XCTAssertEqual(FlagValueBox(displayString: "3.5", as: .double), .double(3.5))
        XCTAssertEqual(FlagValueBox(displayString: #"["a"]"#, as: .array(.string)), .array([.string("a")]))
    }

    func testUnparseableTextIsRejectedRatherThanGuessed() {
        XCTAssertNil(FlagValueBox(displayString: "lots", as: .int))
        XCTAssertNil(FlagValueBox(displayString: "not json", as: .array(.string)))
        XCTAssertNil(FlagValueBox(displayString: "", as: .int))
    }

    // MARK: - Transport

    func testExportCarriesOnlyOverrides() throws {
        try store.setValue(.int(3), for: XCTUnwrap(store.entry(for: "max-items")))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try store.export(as: .json)) as? [String: Any]
        )
        XCTAssertEqual(try XCTUnwrap(object["values"] as? [String: Any]).count, 1)
    }

    func testImportAppliesOverrides() throws {
        let other = FlagEditingStore(
            schema: FlagSchema(CompanionFlags.self),
            source: SnapshotSource(name: "other")
        )
        try other.setValue(.int(3), for: XCTUnwrap(other.entry(for: "max-items")))

        try store.import(try other.export(as: .json), as: .json)
        XCTAssertEqual(store.value(for: try XCTUnwrap(store.entry(for: "max-items"))), .int(3))
    }

    func testQRCodeRoundTripsThroughTheStore() throws {
        try store.setValue(.bool(true), for: XCTUnwrap(store.entry(for: "new-onboarding")))

        let other = FlagEditingStore(
            schema: FlagSchema(CompanionFlags.self),
            source: SnapshotSource(name: "other")
        )
        try other.importQRCode(try store.qrCodeString())

        XCTAssertEqual(other.overriddenKeys, ["new-onboarding"])
    }
}

// MARK: - Fixtures

private enum CompanionTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
}

@FlagContainer
private struct CompanionFlags {

    @Flag(default: false, description: "New onboarding experience")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Maximum items")
    var maxItems: Int

    @FlagGroup(description: "Checkout")
    var checkout: CompanionCheckoutFlags
}

@FlagContainer
private struct CompanionCheckoutFlags {

    @Flag(default: false, description: "Apple Pay")
    var applePay: Bool

    @Flag(default: 1.0, description: "Ratio")
    var ratio: Double

    @Flag(default: CompanionTier.free, description: "Tier")
    var tier: CompanionTier

    @Flag(default: Date(timeIntervalSince1970: 0), description: "Launched at")
    var launchedAt: Date

    @Flag(default: URL(string: "https://example.com")!, description: "Endpoint")
    var endpoint: URL

    @FlagGroup(description: "Express")
    var express: CompanionExpressFlags
}

@FlagContainer
private struct CompanionExpressFlags {

    @Flag(default: "", description: "Label")
    var label: String

    @Flag(default: [], description: "Tags")
    var tags: [String]
}
