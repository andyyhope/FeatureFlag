import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// The companion reads the description from the schema like everything else, so a host
/// that adds one needs no companion rebuild.
final class FlagContainerDescriptionUITests: XCTestCase {

    func testTheStoreSurfacesTheHostsDescription() {
        let store = FlagEditingStore(
            schema: FlagSchema(DescribedUIFlags.self),
            source: SnapshotSource(name: "s")
        )

        XCTAssertEqual(store.schema.description, "What the checkout team can turn on")
    }

    func testAHostWithoutOneSurfacesNothing() {
        let store = FlagEditingStore(
            schema: FlagSchema(PlainUIFlags.self),
            source: SnapshotSource(name: "s")
        )

        XCTAssertNil(store.schema.description)
    }

    func testARefreshPicksUpADescriptionAddedByTheHost() {
        // The host is rebuilt while the companion stays open, which is the whole reason
        // the schema is re-read on return.
        var published = FlagSchema(PlainUIFlags.self)
        let store = FlagEditingStore(
            schema: published,
            source: SnapshotSource(name: "s"),
            reloadingSchemaWith: { published }
        )
        XCTAssertNil(store.schema.description)

        published = FlagSchema(DescribedUIFlags.self)
        store.refreshSchema()

        XCTAssertEqual(store.schema.description, "What the checkout team can turn on")
    }
}

// MARK: - Fixtures

@FlagContainer(description: "What the checkout team can turn on")
private struct DescribedUIFlags {

    @Flag(default: false, description: "Onboarding")
    var newOnboarding: Bool
}

@FlagContainer
private struct PlainUIFlags {

    @Flag(default: false, description: "Onboarding")
    var newOnboarding: Bool
}
