import XCTest

@testable import FeatureFlag

/// The boxed representation is the single canonical form that feeds UserDefaults,
/// JSON, PLIST and QR. Every supported type must survive a round trip through it.
final class FlagValueBoxTests: XCTestCase {

    // MARK: - Primitives box to the expected case

    func testBoolBoxesToBoolCase() {
        XCTAssertEqual(true.box, .bool(true))
    }

    func testIntBoxesToIntCase() {
        XCTAssertEqual(42.box, .int(42))
    }

    func testDoubleBoxesToDoubleCase() {
        XCTAssertEqual((3.5 as Double).box, .double(3.5))
    }

    func testFloatBoxesToFloatCase() {
        XCTAssertEqual((3.5 as Float).box, .float(3.5))
    }

    func testStringBoxesToStringCase() {
        XCTAssertEqual("hello".box, .string("hello"))
    }

    func testDataBoxesToDataCase() {
        let data = Data([0x01, 0x02])
        XCTAssertEqual(data.box, .data(data))
    }

    func testDateBoxesToDateCase() {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(date.box, .date(date))
    }

    func testURLBoxesToURLCase() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(url.box, .url(url))
    }

    // MARK: - Primitives round trip

    func testBoolRoundTrips() {
        XCTAssertEqual(Bool(box: false.box), false)
    }

    func testIntRoundTrips() {
        XCTAssertEqual(Int(box: (-7).box), -7)
    }

    func testDoubleRoundTrips() {
        XCTAssertEqual(Double(box: (3.5 as Double).box), 3.5)
    }

    func testFloatRoundTrips() {
        XCTAssertEqual(Float(box: (3.5 as Float).box), 3.5)
    }

    func testStringRoundTrips() {
        XCTAssertEqual(String(box: "hello".box), "hello")
    }

    func testDataRoundTrips() {
        let data = Data([0x01, 0x02])
        XCTAssertEqual(Data(box: data.box), data)
    }

    func testDateRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(Date(box: date.box), date)
    }

    func testURLRoundTrips() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(URL(box: url.box), url)
    }

    // MARK: - Unboxing is strict

    func testUnboxingRejectsMismatchedCase() {
        XCTAssertNil(Bool(box: .int(1)))
        XCTAssertNil(Int(box: .string("1")))
        XCTAssertNil(String(box: .bool(true)))
        XCTAssertNil(Double(box: .int(1)))
    }

    // MARK: - Declared value types

    func testPrimitivesDeclareTheirValueType() {
        XCTAssertEqual(Bool.flagValueType, .bool)
        XCTAssertEqual(Int.flagValueType, .int)
        XCTAssertEqual(Double.flagValueType, .double)
        XCTAssertEqual(Float.flagValueType, .float)
        XCTAssertEqual(String.flagValueType, .string)
        XCTAssertEqual(Data.flagValueType, .data)
        XCTAssertEqual(Date.flagValueType, .date)
        XCTAssertEqual(URL.flagValueType, .url)
    }
}
