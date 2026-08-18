import Combine
import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// The companion read its host's schema once and kept it for the life of the process,
/// so a host that added a flag was invisible until someone force quit the companion —
/// which looks exactly like the App Group being misconfigured.
final class FlagSchemaReloadTests: XCTestCase {

    private func entry(_ key: FlagKey, _ description: String) -> FlagSchema.Entry {
        FlagSchema.Entry(
            key: key,
            propertyPath: [key.rawValue],
            description: description,
            valueType: .bool,
            defaultValue: .bool(false)
        )
    }

    func testRefreshingPicksUpAFlagThatDidNotExistBefore() {
        var published = FlagSchema(flags: [entry("one", "One")])
        let store = FlagEditingStore(
            schema: published,
            source: SnapshotSource(name: "shared"),
            reloadingSchemaWith: { published }
        )

        XCTAssertEqual(store.schema.flags.count, 1)

        published = FlagSchema(flags: [entry("one", "One"), entry("two", "Two")])
        store.refreshSchema()

        XCTAssertEqual(store.schema.flags.map(\.key), ["one", "two"])
    }

    func testRefreshingTellsSwiftUISomethingChanged() {
        var published = FlagSchema(flags: [entry("one", "One")])
        let store = FlagEditingStore(
            schema: published,
            source: SnapshotSource(name: "shared"),
            reloadingSchemaWith: { published }
        )

        var changes = 0
        let cancellable = store.objectWillChange.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        published = FlagSchema(flags: [entry("one", "One"), entry("two", "Two")])
        store.refreshSchema()

        XCTAssertEqual(changes, 1)
    }

    func testRefreshingWhenNothingChangedDoesNotChurnTheView() {
        // Called on every foreground, so the common case has to be free — and a view
        // rebuilt for nothing loses whatever the user had selected or was typing.
        let published = FlagSchema(flags: [entry("one", "One")])
        let store = FlagEditingStore(
            schema: published,
            source: SnapshotSource(name: "shared"),
            reloadingSchemaWith: { published }
        )

        var changes = 0
        let cancellable = store.objectWillChange.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        store.refreshSchema()

        XCTAssertEqual(changes, 0)
    }

    func testAHostThatHasStoppedPublishingLeavesTheLastSchemaInPlace() {
        // Better a stale editor than an empty one: the host may simply not be running,
        // and blanking the screen would read as "this app has no flags".
        let published = FlagSchema(flags: [entry("one", "One")])
        let store = FlagEditingStore(
            schema: published,
            source: SnapshotSource(name: "shared"),
            reloadingSchemaWith: { nil }
        )

        store.refreshSchema()

        XCTAssertEqual(store.schema.flags.map(\.key), ["one"])
    }

    func testAStoreBuiltWithoutAReloaderIsUnaffected() {
        let store = FlagEditingStore(
            schema: FlagSchema(flags: [entry("one", "One")]),
            source: SnapshotSource(name: "shared")
        )

        store.refreshSchema()

        XCTAssertEqual(store.schema.flags.map(\.key), ["one"])
    }
}
