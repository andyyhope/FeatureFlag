import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// Filing signals into groups, and deciding which of them earn a screen.
final class FlagSignalGroupTests: XCTestCase {

    // MARK: - Automatic nesting

    func testASmallGroupStaysFlat() {
        let group = FlagSignalGroup.group("Session", SmallSignal.self)
        XCTAssertEqual(group.signals.count, 2)
        XCTAssertFalse(group.isNested)
    }

    /// Six fits beside the delay picker; a seventh is where a list starts to bury it.
    func testAGroupNestsOnceItPassesTheThreshold() {
        XCTAssertEqual(FlagSignalGroup.automaticNestingThreshold, 6)
        XCTAssertEqual(SixSignal.allCases.count, 6)
        XCTAssertEqual(SevenSignal.allCases.count, 7)

        XCTAssertFalse(FlagSignalGroup.group("Six", SixSignal.self).isNested)
        XCTAssertTrue(FlagSignalGroup.group("Seven", SevenSignal.self).isNested)
    }

    func testTheThresholdCanBeMoved() {
        FlagSignalGroup.automaticNestingThreshold = 1
        defer { FlagSignalGroup.automaticNestingThreshold = 6 }

        XCTAssertTrue(FlagSignalGroup.group("Session", SmallSignal.self).isNested)
    }

    func testAnExplicitDisplayOverridesTheCount() {
        XCTAssertTrue(FlagSignalGroup.group("Session", SmallSignal.self, display: .nested).isNested)
        XCTAssertFalse(FlagSignalGroup.group("Seven", SevenSignal.self, display: .flat).isNested)
    }

    // MARK: - Contents

    func testAGroupCarriesEachSignalsDescriptionAndRestartFlag() throws {
        let group = FlagSignalGroup.group("Session", SmallSignal.self)

        let signOut = try XCTUnwrap(group.signals.first { $0.id == "signOut" })
        XCTAssertEqual(signOut.description, "Sign out")
        XCTAssertFalse(signOut.requiresRestart)

        let swap = try XCTUnwrap(group.signals.first { $0.id == "swapDependency" })
        XCTAssertTrue(swap.requiresRestart)
    }

    func testGroupsKeepTheOrderTheyAreGivenAndSoDoTheirSignals() {
        let groups: [FlagSignalGroup] = [
            .group("Session", SmallSignal.self),
            .group("Six", SixSignal.self),
        ]
        XCTAssertEqual(groups.map(\.title), ["Session", "Six"])
        XCTAssertEqual(groups[0].signals.map(\.id), SmallSignal.allCases.map(\.rawValue))
    }

    // MARK: - Collisions

    /// A signal travels as its raw value and nothing else, so the same one in two groups
    /// means both of the host's observers fire for a single press.
    func testTwoGroupsSharingARawValueAreDetected() {
        let groups: [FlagSignalGroup] = [
            .group("A", SmallSignal.self),
            .group("B", CollidingSignal.self),
        ]
        XCTAssertEqual(groups.duplicateSignalID, "signOut")
    }

    func testDistinctGroupsDoNotCollide() {
        let groups: [FlagSignalGroup] = [
            .group("Session", SmallSignal.self),
            .group("Six", SixSignal.self),
        ]
        XCTAssertNil(groups.duplicateSignalID)
    }

    // MARK: - The view

    func testTheGroupedViewBuilds() {
        let view = FlagSignalsView(
            groups: [.group("Session", SmallSignal.self), .group("Seven", SevenSignal.self)],
            appGroup: "group.example.flags"
        )
        XCTAssertNotNil(view.body)
    }

    /// The single-type form still works and reads as one flat, unnamed group.
    func testTheSingleTypeFormIsOneFlatGroup() {
        XCTAssertNotNil(FlagSignalsView(SmallSignal.self, appGroup: "group.example.flags").body)
    }

    func testTheGroupedTabDescriptor() {
        let tab = FlagCompanionTab.signals(
            [.group("Session", SmallSignal.self)], appGroup: "group.example.flags"
        )
        XCTAssertEqual(tab.id, "signals")
        XCTAssertEqual(tab.title, "Signals")
    }
}

private enum SmallSignal: String, FlagSignal, CaseIterable {
    case signOut
    case swapDependency

    var signalDescription: String { self == .signOut ? "Sign out" : "Swap dependency" }
    var requiresRestart: Bool { self == .swapDependency }
}

private enum CollidingSignal: String, FlagSignal {
    case signOut
}

private enum SixSignal: String, FlagSignal {
    case a, b, c, d, e, f
}

private enum SevenSignal: String, FlagSignal {
    case a, b, c, d, e, f, g
}
