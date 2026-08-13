import FeatureFlag
import SwiftUI
import XCTest

import FeatureFlagUI

/// Every code sample in the FeatureFlagUI DocC catalog, compiled and run.
///
/// The samples live in `Sources/FeatureFlagUI/FeatureFlagUI.docc`; change one there and
/// change it here.
final class UIDocumentationExampleTests: XCTestCase {

    private func makeStore() -> FlagEditingStore {
        FlagEditingStore(
            schema: FlagSchema(CompanionDocsFlags.self),
            source: SnapshotSource(name: "shared")
        )
    }

    // MARK: - FeatureFlagUI.md

    /// The landing page's app: a store from a group, rendering the overrides screen.
    func testTheLandingPageCompanionCompiles() {
        let store = makeStore()
        XCTAssertNotNil(FlagOverridesView(store: store).body)
    }

    /// The claim that the two screens share one store.
    func testBothScreensTakeTheSameStore() {
        let store = makeStore()

        XCTAssertNotNil(FlagOverridesView(store: store).body)
        XCTAssertNotNil(FlagBrowserView(store: store).body)
    }

    // MARK: - BuildingACompanionApp.md

    /// Step two: the group initialiser throws rather than traps when it cannot be used,
    /// which is what lets the sample distinguish it from an empty list.
    func testTheGroupInitialiserThrowsWhenUnavailable() {
        XCTAssertThrowsError(try FlagEditingStore(appGroup: "group.example.missing.\(UUID())"))
    }

    /// Step three: the tabbed root view.
    func testTheTabbedRootViewCompiles() {
        XCTAssertNotNil(CompanionRootView(store: makeStore()).body)
    }

    /// The "editing something other than an App Group" sample.
    func testAStoreCanBeBuiltFromASchemaOnDisk() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FlagSchema(CompanionDocsFlags.self).write(toDirectory: directory)

        let schema = try FlagSchema(contentsOfDirectory: directory)
        let store = FlagEditingStore(schema: schema, source: SnapshotSource(name: "Preview"))

        XCTAssertEqual(store.schema.flags.map(\.key), ["new-onboarding", "checkout.apple-pay"])
    }

    /// The preview sample, which builds a schema by hand rather than from a container.
    func testTheHandBuiltSchemaPreviewSampleCompiles() {
        let store = FlagEditingStore(
            schema: FlagSchema(
                flags: [
                    FlagSchema.Entry(
                        key: "new-onboarding",
                        propertyPath: ["newOnboarding"],
                        description: "Show the redesigned onboarding",
                        valueType: .bool,
                        defaultValue: .bool(false)
                    )
                ]
            ),
            source: SnapshotSource(name: "Preview")
        )

        XCTAssertNotNil(FlagBrowserView(store: store).body)
        XCTAssertEqual(store.tree.flags.map(\.key), ["new-onboarding"])
    }

    /// Everything the "building your own screens" sample reaches for.
    func testTheCustomScreenSampleAPIsBehaveAsWritten() throws {
        let store = makeStore()
        let entry = try XCTUnwrap(store.entry(for: "checkout.apple-pay"))

        XCTAssertEqual(store.tree.flags.map(\.key), ["new-onboarding"])
        XCTAssertEqual(store.tree.groups.map(\.title), ["Checkout"])
        XCTAssertEqual(store.sections.flatMap(\.entries).count, 2)
        XCTAssertTrue(store.overriddenKeys.isEmpty)

        XCTAssertEqual(store.value(for: entry), .bool(false))
        XCTAssertFalse(store.isOverridden(entry))

        try store.setValue(.bool(true), for: entry)
        XCTAssertTrue(store.isOverridden(entry))
        XCTAssertEqual(store.overriddenKeys, ["checkout.apple-pay"])
        XCTAssertEqual(store.overriddenCount(in: store.tree.groups[0]), 1)

        try store.reset(entry)
        XCTAssertFalse(store.isOverridden(entry))

        try store.setValue(.bool(true), for: entry)
        try store.resetAll()
        XCTAssertTrue(store.overriddenKeys.isEmpty)
    }

    /// The custom list sample.
    func testTheCustomListSampleCompiles() {
        let store = makeStore()
        let view = List {
            ForEach(store.tree.flags, id: \.key) { entry in
                FlagRowView(store: store, entry: entry)
            }
        }
        XCTAssertNotNil(view.body)
    }

    /// The transport sample.
    func testTheTransportSampleRoundTrips() throws {
        let store = makeStore()
        let entry = try XCTUnwrap(store.entry(for: "new-onboarding"))
        try store.setValue(.bool(true), for: entry)

        let json = try store.export(as: .json)
        let code = try store.qrCodeString()

        let destination = makeStore()
        try destination.import(json, as: .json)
        XCTAssertEqual(destination.overriddenKeys, ["new-onboarding"])

        try destination.resetAll()
        try destination.importQRCode(code)
        XCTAssertEqual(destination.overriddenKeys, ["new-onboarding"])
    }

    /// The claim that an override the host would ignore is not shown as one.
    func testAnOverrideTheHostWouldIgnoreIsNotShown() throws {
        let source = SnapshotSource(name: "shared")
        let store = FlagEditingStore(schema: FlagSchema(CompanionDocsFlags.self), source: source)
        let entry = try XCTUnwrap(store.entry(for: "new-onboarding"))

        // A hand-edited suite holding the wrong type for this flag.
        try source.setBox(.string("true"), for: "new-onboarding")

        XCTAssertFalse(store.isOverridden(entry))
        XCTAssertEqual(store.value(for: entry), .bool(false), "it falls back, as the host does")
    }
}

// MARK: - Fixtures, as the articles write them

/// The tabbed root view from BuildingACompanionApp.md.
private struct CompanionRootView: View {

    let store: FlagEditingStore

    var body: some View {
        TabView {
            FlagOverridesView(store: store)
                .tabItem { Label("Overrides", systemImage: "slider.horizontal.3") }

            FlagBrowserView(store: store)
                .tabItem { Label("Flags", systemImage: "flag") }
        }
    }
}

@FlagContainer
private struct CompanionDocsFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool

    @FlagGroup(description: "Checkout")
    var checkout: CompanionDocsCheckoutFlags
}

@FlagContainer
private struct CompanionDocsCheckoutFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool
}
