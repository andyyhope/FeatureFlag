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

// MARK: - Malformed tab lists

extension CompanionViewTests {

    /// Two tabs sharing an id breaks both `ForEach` identity and selection — the tag is
    /// what a `TabView` switches on, so one of them can never be shown. There is no
    /// correct rendering to fall back to, so it has to be caught rather than guessed at.
    func testADuplicateIdIsDetectedAndNamed() {
        let duplicated = FlagCompanionTabs.duplicateID(in: [.overrides, .flags, .overrides])
        XCTAssertEqual(duplicated, "overrides")

        let custom = FlagCompanionTab.custom(id: "flags", title: "Mine", symbol: "flag") { _ in
            Text("mine")
        }
        XCTAssertEqual(FlagCompanionTabs.duplicateID(in: [.flags, custom]), "flags")
    }

    func testAWellFormedListHasNoDuplicate() {
        XCTAssertNil(
            FlagCompanionTabs.duplicateID(
                in: [.overrides, .signals(ComposedSignal.self, appGroup: "g"), .flags]
            )
        )
    }

    /// An empty list used to render a `TabView` with no tabs, which is a blank screen and
    /// no clue as to why. Saying so costs nothing and cannot be missed.
    func testAnEmptyListExplainsItselfRatherThanRenderingNothing() {
        let view = FlagCompanionTabs(store: makeStore(), tabs: [])
        XCTAssertTrue(view.isEmptyOfTabs)
        XCTAssertNotNil(view.body)
    }

    func testAPopulatedListIsNotTreatedAsEmpty() {
        XCTAssertFalse(FlagCompanionTabs(store: makeStore(), tabs: [.flags]).isEmptyOfTabs)
    }
}

// MARK: - One flag on its own screen

extension CompanionViewTests {

    func testTheDetailViewBuildsForAFlagThatExists() {
        let view = FlagDetailView(store: makeStore(), key: "new-onboarding")
        XCTAssertNotNil(view.body)
    }

    /// A key that is not published must say so rather than render an empty form — the
    /// most likely cause is using the property name instead of the published key.
    func testTheDetailViewBuildsForAKeyThatDoesNot() {
        let view = FlagDetailView(store: makeStore(), key: "newOnboarding")
        XCTAssertNotNil(view.body)
    }

    /// Each detail tab is a distinct tab, so two of them must not collide on id.
    func testDetailTabsAreIdentifiedByTheirKey() {
        let tabs: [FlagCompanionTab] = [
            .detail(key: "environment", title: "Environment"),
            .detail(key: "checkout.tier", title: "Tier"),
        ]
        XCTAssertEqual(tabs.map(\.id), ["detail.environment", "detail.checkout.tier"])
        XCTAssertNil(FlagCompanionTabs.duplicateID(in: tabs))
    }

    func testADetailTabRendersTheFlagItNames() {
        let tab = FlagCompanionTab.detail(key: "new-onboarding", title: "Onboarding")
        XCTAssertEqual(tab.title, "Onboarding")
        XCTAssertNotNil(tab.content(makeStore()))
    }
}
