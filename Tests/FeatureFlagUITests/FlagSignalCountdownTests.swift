import XCTest

import FeatureFlag
@testable import FeatureFlagUI

/// The ring is drawn from the clock rather than animated, so how far round it is at a
/// given moment is plain arithmetic.
final class FlagSignalCountdownTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testTheRingIsEmptyWhenTheCountdownStarts() {
        let countdown = FlagSignalCountdown(start: start, duration: 5)
        XCTAssertEqual(countdown.progress(at: start), 0)
    }

    func testTheRingIsHalfwayHalfwayThrough() {
        let countdown = FlagSignalCountdown(start: start, duration: 10)
        XCTAssertEqual(countdown.progress(at: start.addingTimeInterval(5)), 0.5)
    }

    func testTheRingIsFullOnceTheDelayHasPassed() {
        // A companion returning from the background after the send should show a full
        // ring, not one that picks up where the render server left it.
        let countdown = FlagSignalCountdown(start: start, duration: 3)
        XCTAssertEqual(countdown.progress(at: start.addingTimeInterval(30)), 1)
    }

    func testTheRingNeverRunsBackwards() {
        let countdown = FlagSignalCountdown(start: start, duration: 3)
        XCTAssertEqual(countdown.progress(at: start.addingTimeInterval(-1)), 0)
    }

    func testTheIntervalRunsFromTheTapToWhenTheSignalFires() {
        // What the Live Activity's ring drains across, so it empties as the send goes.
        let countdown = FlagSignalCountdown(start: start, duration: 5)
        XCTAssertEqual(countdown.interval, start...start.addingTimeInterval(5))
    }

    @MainActor
    func testSchedulingASignalStartsACountdownForTheChosenDelay() throws {
        let model = FlagSignalsModel(appGroup: "group.test.countdown", timeout: 1)
        let signal = try XCTUnwrap(FlagSignalGroup.group("", CountdownSignal.self).signals.first)
        model.delay = .five

        let before = Date()
        model.tapped(signal)

        let countdown = try XCTUnwrap(model.countdown)
        XCTAssertEqual(model.pending, signal)
        XCTAssertEqual(countdown.duration, 5)
        XCTAssertGreaterThanOrEqual(countdown.start, before)
        model.cancelPending()
    }

    @MainActor
    func testCancellingClearsTheCountdown() throws {
        let model = FlagSignalsModel(appGroup: "group.test.countdown", timeout: 1)
        let signal = try XCTUnwrap(FlagSignalGroup.group("", CountdownSignal.self).signals.first)
        model.delay = .three
        model.tapped(signal)

        model.tapped(signal)

        XCTAssertNil(model.pending)
        XCTAssertNil(model.countdown)
    }
}

private enum CountdownSignal: String, FlagSignal {
    case purge
}
