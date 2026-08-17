import XCTest

@testable import FeatureFlag

final class RemoteValueTests: XCTestCase {

    private func decoded(_ json: String) throws -> RemoteValue {
        RemoteValue(deserialised: try JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    // MARK: - Deserialising

    func testBooleansAreNotMistakenForNumbers() throws {
        let value = try decoded(#"{"a": true, "b": 1}"#)
        XCTAssertEqual(value.value(atPath: "a"), .bool(true))
        XCTAssertEqual(value.value(atPath: "b"), .int(1))
    }

    func testWholeAndFractionalNumbersAreDistinguished() throws {
        let value = try decoded(#"{"a": 1, "b": 1.5}"#)
        XCTAssertEqual(value.value(atPath: "a"), .int(1))
        XCTAssertEqual(value.value(atPath: "b"), .double(1.5))
    }

    func testNullBecomesNull() throws {
        XCTAssertEqual(try decoded(#"{"a": null}"#).value(atPath: "a"), .null)
    }

    func testNestingIsPreserved() throws {
        let value = try decoded(#"{"a": {"b": [1, 2]}}"#)
        XCTAssertEqual(value.value(atPath: "a.b"), .array([.int(1), .int(2)]))
    }

    func testPropertyListDatesAndDataSurviveDeserialising() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["d": Date(timeIntervalSince1970: 5), "b": Data([0x01])],
            format: .xml,
            options: 0
        )
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let value = RemoteValue(deserialised: object)

        XCTAssertEqual(value.value(atPath: "d"), .date(Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(value.value(atPath: "b"), .data(Data([0x01])))
    }

    // MARK: - Paths

    func testAnEmptyPathReturnsTheRoot() throws {
        let value = try decoded(#"{"a": 1}"#)
        XCTAssertEqual(value.value(atPath: ""), value)
    }

    func testAMissingKeyReturnsNothing() throws {
        XCTAssertNil(try decoded(#"{"a": 1}"#).value(atPath: "b"))
        XCTAssertNil(try decoded(#"{"a": 1}"#).value(atPath: "a.b"))
    }

    func testAnIndexPastTheEndReturnsNothing() throws {
        XCTAssertNil(try decoded(#"{"a": [1]}"#).value(atPath: "a.5"))
    }

    func testANegativeIndexReturnsNothing() throws {
        XCTAssertNil(try decoded(#"{"a": [1]}"#).value(atPath: "a.-1"))
    }

    func testANonNumericComponentOnAnArrayReturnsNothing() throws {
        XCTAssertNil(try decoded(#"{"a": [1]}"#).value(atPath: "a.first"))
    }

    func testDescendingIntoAScalarReturnsNothing() throws {
        XCTAssertNil(try decoded(#"{"a": 1}"#).value(atPath: "a.b.c"))
    }

    func testDeepPathsResolve() throws {
        let value = try decoded(#"{"a": {"b": [{"c": {"d": true}}]}}"#)
        XCTAssertEqual(value.value(atPath: "a.b.0.c.d"), .bool(true))
    }

    // MARK: - Boxing

    func testStringsBecomeDatesDataAndURLsWhereDeclared() {
        XCTAssertEqual(
            RemoteValue.string("1970-01-01T00:00:00Z").box(as: .date),
            .date(Date(timeIntervalSince1970: 0))
        )
        XCTAssertEqual(RemoteValue.string("AQI=").box(as: .data), .data(Data([0x01, 0x02])))
        XCTAssertEqual(
            RemoteValue.string("https://a.example").box(as: .url),
            .url(URL(string: "https://a.example")!)
        )
    }

    func testAnUnparseableStringIsRejectedForEachStructuredType() {
        XCTAssertNil(RemoteValue.string("not a date").box(as: .date))
        XCTAssertNil(RemoteValue.string("!!!not base64!!!").box(as: .data))
    }

    func testNullNeverBoxes() {
        for type in [FlagValueType.bool, .int, .string, .array(.int)] {
            XCTAssertNil(RemoteValue.null.box(as: type))
        }
    }

    func testWideningIsExactAndOnlyUpwards() {
        XCTAssertEqual(RemoteValue.int(1).box(as: .double), .double(1))
        XCTAssertEqual(RemoteValue.int(1).box(as: .float), .float(1))
        XCTAssertNil(RemoteValue.double(1.5).box(as: .int))
        XCTAssertNil(RemoteValue.double(1.0).box(as: .int))
    }

    func testBooleansAndNumbersNeverConvertIntoEachOther() {
        XCTAssertNil(RemoteValue.int(1).box(as: .bool))
        XCTAssertNil(RemoteValue.bool(true).box(as: .int))
        XCTAssertNil(RemoteValue.string("true").box(as: .bool))
    }

    func testCollectionsBoxElementByElement() {
        XCTAssertEqual(
            RemoteValue.array([.int(1), .int(2)]).box(as: .array(.int)),
            .array([.int(1), .int(2)])
        )
        XCTAssertNil(RemoteValue.array([.int(1), .string("x")]).box(as: .array(.int)))
    }

    func testAnEmptyCollectionBoxesAsAnyElementType() {
        XCTAssertEqual(RemoteValue.array([]).box(as: .array(.date)), .array([]))
        XCTAssertEqual(RemoteValue.object([:]).box(as: .dictionary(.url)), .dictionary([:]))
    }

    func testCollectionsWidenTheirElementsToo() {
        XCTAssertEqual(
            RemoteValue.array([.int(1)]).box(as: .array(.double)),
            .array([.double(1)])
        )
    }
}

// MARK: - The types only a property list carries natively

extension RemoteValueTests {

    /// JSON has no date and no data, so these two branches are reachable only from a
    /// property list. Strings becoming dates and data is tested above; this is the
    /// value arriving already typed.
    func testNativeDatesAndDataBoxAsThemselves() {
        let moment = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RemoteValue.date(moment).box(as: .date), .date(moment))

        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(RemoteValue.data(bytes).box(as: .data), .data(bytes))
    }

    /// A native date is not a string, and must not satisfy a string flag by being
    /// described into one.
    func testNativeDatesAndDataDoNotSatisfyOtherTypes() {
        let moment = RemoteValue.date(Date(timeIntervalSince1970: 1_000))
        for type in [FlagValueType.string, .int, .double, .bool, .data, .url] {
            XCTAssertNil(moment.box(as: type), "a date should not box as \(type)")
        }

        let bytes = RemoteValue.data(Data([0x01]))
        for type in [FlagValueType.string, .int, .double, .bool, .date, .url] {
            XCTAssertNil(bytes.box(as: type), "data should not box as \(type)")
        }
    }
}
