import XCTest

@testable import FeatureFlagUI

/// The delay itself is testable even though the animation that visualises it is not.
final class FlagSignalDelayTests: XCTestCase {

    func testTheOfferedDelaysAreInstantThreeFiveAndTen() {
        XCTAssertEqual(FlagSignalDelay.allCases.map(\.rawValue), [0, 3, 5, 10])
    }

    func testInstantIsLabelledAsSuchAndTheRestInSeconds() {
        XCTAssertEqual(FlagSignalDelay.allCases.map(\.label), ["Instant", "3s", "5s", "10s"])
    }

    func testInstantIsTheOnlyZeroDelay() {
        // The view branches on this: zero sends immediately, anything else schedules a
        // countdown the user can cancel.
        XCTAssertEqual(FlagSignalDelay.allCases.filter { $0.rawValue == 0 }, [.instant])
    }

    func testDelaysAreDistinctAndAscending() {
        let values = FlagSignalDelay.allCases.map(\.rawValue)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(Set(values).count, values.count)
    }
}
