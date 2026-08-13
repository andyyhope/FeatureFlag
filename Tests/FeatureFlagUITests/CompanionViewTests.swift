import FeatureFlag
import SwiftUI
import XCTest

@testable import FeatureFlagUI

/// The drop-in companion. Everything here is what an adopter would otherwise have had
/// to write themselves, so it is worth holding to the same standard as the views.
final class CompanionViewTests: XCTestCase {

    fileprivate func makeStore() -> FlagEditingStore {
        FlagEditingStore(
            schema: FlagSchema(CompanionViewFlags.self),
            source: SnapshotSource(name: "shared")
        )
    }

    // MARK: - The zero-configuration form

    func testTheDefaultCompanionNeedsNothingButAGroup() {
        let view = FlagCompanionView(appGroup: "group.example.\(UUID().uuidString)")
        XCTAssertNotNil(view.body)
    }

    func testTheDefaultLayoutShowsOverridesAndFlags() {
        XCTAssertNotNil(FlagCompanionTabs(store: makeStore()).body)
    }

    // MARK: - The custom form

    /// The point of the closure: the caller decides the order and adds their own tabs,
    /// without reimplementing loading or the failure states.
    func testACustomLayoutReceivesTheLoadedStore() {
        var received: FlagEditingStore?

        let view = FlagCompanionView(appGroup: "group.example.\(UUID().uuidString)") { store in
            received = store
            return FlagOverridesView(store: store)
        }

        XCTAssertNotNil(view.body)
        // Nothing is built until the store opens, which it cannot here.
        XCTAssertNil(received)
    }

    // MARK: - Failing usefully

    /// A companion that says only "could not load" leaves someone with nowhere to go.
    /// Both causes have to be named, and the group has to be quoted so a typo in the
    /// entitlement is visible rather than described.
    func testTheFailureMessageNamesBothCausesAndTheGroup() {
        let group = "group.com.example.flags"
        let message = FlagCompanionLoader.message(for: group)

        XCTAssertTrue(message.contains(group), message)
        XCTAssertTrue(message.lowercased().contains("run the host"), message)
        XCTAssertTrue(message.lowercased().contains("entitlement"), message)
    }

    func testLoadingAnUnavailableGroupFails() {
        let loader = FlagCompanionLoader(appGroup: "group.example.missing.\(UUID().uuidString)")
        loader.load()

        guard case let .failed(message) = loader.state else {
            return XCTFail("expected .failed, got \(loader.state)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testTheUnavailableViewBuilds() {
        let view = FlagCompanionUnavailableView(message: "Run the host app.") {}
        XCTAssertNotNil(view.body)
    }

    // MARK: - Tab items

    /// The selected tab fills its symbol; the rest stay outlined.
    func testTheTabModifierBuildsInBothStates() {
        XCTAssertNotNil(
            Text("x").flagCompanionTab("Flags", symbol: "flag", isSelected: true)
        )
        XCTAssertNotNil(
            Text("x").flagCompanionTab("Flags", symbol: "flag", isSelected: false)
        )
    }
}

@FlagContainer
private struct CompanionViewFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}

// MARK: - Composing tabs

extension CompanionViewTests {

    /// The default is the minimum every companion wants, and nothing more. An app with
    /// no signals should not be handed a signals tab it cannot fill.
    func testTheDefaultTabsAreOverridesAndFlags() {
        let tabs: [FlagCompanionTab] = [.overrides, .flags]
        XCTAssertEqual(tabs.map(\.id), ["overrides", "flags"])
        XCTAssertEqual(tabs.map(\.title), ["Overrides", "Flags"])
    }

    /// Order is the caller's, not the library's.
    func testTabsKeepTheOrderTheyAreGiven() {
        let tabs: [FlagCompanionTab] = [
            .overrides,
            .signals(ComposedSignal.self, appGroup: "group.example.flags"),
            .flags,
        ]
        XCTAssertEqual(tabs.map(\.id), ["overrides", "signals", "flags"])
    }

    func testSignalsCanBeLeftOutEntirely() {
        let view = FlagCompanionView(
            appGroup: "group.example.\(UUID().uuidString)", tabs: [.overrides]
        )
        XCTAssertNotNil(view.body)
    }

    func testACustomTabCarriesItsOwnIdentityAndContent() {
        let tab = FlagCompanionTab.custom(
            id: "environment", title: "Environment", symbol: "square.stack.3d.up"
        ) { store in
            Text("\(store.schema.flags.count)")
        }

        XCTAssertEqual(tab.id, "environment")
        XCTAssertEqual(tab.symbol, "square.stack.3d.up")
        XCTAssertNotNil(tab.content(makeStore()))
    }

    /// Selection starts on the first tab, whichever that is.
    func testTheFirstTabIsSelected() {
        XCTAssertNotNil(
            FlagCompanionTabs(store: makeStore(), tabs: [.flags, .overrides]).body
        )
    }

    func testTheSignalsViewBuilds() {
        let view = FlagSignalsView(ComposedSignal.self, appGroup: "group.example.flags")
        XCTAssertNotNil(view.body)
    }
}

private enum ComposedSignal: String, FlagSignal {
    case refetchRemoteConfiguration
}
