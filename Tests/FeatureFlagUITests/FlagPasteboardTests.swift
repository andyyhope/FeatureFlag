import XCTest

@testable import FeatureFlagUI

final class FlagPasteboardTests: XCTestCase {

    func testCopyingPutsTheValueOnThePasteboard() {
        let payload = #"{"a":1,"b":["x","y"]}"#
        FlagPasteboard.copy(payload)
        XCTAssertEqual(FlagPasteboard.current, payload)
    }

    func testCopyingReplacesWhateverWasThereBefore() {
        FlagPasteboard.copy("first")
        FlagPasteboard.copy("second")
        XCTAssertEqual(FlagPasteboard.current, "second")
    }

    func testCopyingAnEmptyStringIsNotACrash() {
        FlagPasteboard.copy("")
        XCTAssertEqual(FlagPasteboard.current, "")
    }
}
