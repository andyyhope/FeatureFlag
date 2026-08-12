import FeatureFlag
import SwiftUI
import XCTest

import FeatureFlagUI

/// The companion snippet from README.md, compiled.
final class READMECompanionExampleTests: XCTestCase {

    func testCompanionSnippetBuildsAnEditor() throws {
        let store = FlagEditingStore(
            schema: FlagSchema(ReadmeCompanionFlags.self),
            source: SnapshotSource(name: "shared")
        )

        // As written in the README, modulo the App Group the test cannot open.
        let view = FlagBrowserView(store: store)
        XCTAssertNotNil(view.body)

        XCTAssertEqual(store.sections.flatMap(\.entries).map(\.key), ["new-onboarding"])
    }

    func testTheAppGroupInitialiserIsTheDocumentedShape() {
        // The README tells people to write this; it must at least exist and throw
        // rather than trap when the group is unavailable.
        XCTAssertThrowsError(try FlagEditingStore(appGroup: "group.example.missing.\(UUID())"))
    }
}

@FlagContainer
private struct ReadmeCompanionFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}
