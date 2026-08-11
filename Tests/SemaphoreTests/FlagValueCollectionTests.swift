import XCTest

@testable import Semaphore

final class FlagValueCollectionTests: XCTestCase {

    // MARK: - Arrays

    func testArrayBoxesEachElement() {
        XCTAssertEqual([true, false].box, .array([.bool(true), .bool(false)]))
    }

    func testArrayRoundTrips() {
        let values = ["a", "b", "c"]
        XCTAssertEqual([String](box: values.box), values)
    }

    func testEmptyArrayRoundTrips() {
        XCTAssertEqual([Int](box: [Int]().box), [])
    }

    func testNestedArrayRoundTrips() {
        let values = [[1, 2], [3]]
        XCTAssertEqual([[Int]](box: values.box), values)
    }

    func testArrayRejectsElementOfTheWrongType() {
        XCTAssertNil([Int](box: .array([.int(1), .string("2")])))
    }

    func testArrayReportsItsElementType() {
        XCTAssertEqual([Bool].flagValueType, .array(.bool))
    }

    // MARK: - Dictionaries

    func testDictionaryBoxesEachValue() {
        XCTAssertEqual(["a": 1].box, .dictionary(["a": .int(1)]))
    }

    func testDictionaryRoundTrips() {
        let values = ["a": 1, "b": 2]
        XCTAssertEqual([String: Int](box: values.box), values)
    }

    func testDictionaryRejectsValueOfTheWrongType() {
        XCTAssertNil([String: Int](box: .dictionary(["a": .int(1), "b": .bool(true)])))
    }

    func testDictionaryReportsItsValueType() {
        XCTAssertEqual([String: Double].flagValueType, .dictionary(.double))
    }

    // MARK: - Enums

    func testStringBackedEnumRoundTrips() {
        XCTAssertEqual(Tier(box: Tier.pro.box), .pro)
    }

    func testStringBackedEnumBoxesAsItsRawValue() {
        XCTAssertEqual(Tier.pro.box, .string("pro"))
    }

    func testIntBackedEnumRoundTrips() {
        XCTAssertEqual(Level(box: Level.high.box), .high)
    }

    func testEnumReportsItsRawValueType() {
        XCTAssertEqual(Tier.flagValueType, .string)
        XCTAssertEqual(Level.flagValueType, .int)
    }

    func testEnumRejectsUnknownRawValue() {
        XCTAssertNil(Tier(box: .string("enterprise")))
    }

    func testEnumRejectsMismatchedBoxType() {
        XCTAssertNil(Tier(box: .int(1)))
    }

    // MARK: - Case listing

    func testCaseIterableEnumSurfacesItsCasesForEditors() {
        XCTAssertEqual(Tier.flagValueCases, [.string("free"), .string("pro")])
    }

    func testCasesAreDiscoverableWithoutGenerics() {
        // The schema layer only ever has a metatype, never a concrete generic context,
        // so cases must be reachable through an existential.
        let type: any FlagValue.Type = Tier.self
        XCTAssertEqual((type as? any FlagValueCases.Type)?.flagValueCases, [.string("free"), .string("pro")])
    }

    func testNonCaseIterableEnumIsNotCaseListable() {
        let type: any FlagValue.Type = Level.self
        XCTAssertNil(type as? any FlagValueCases.Type)
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
}

private enum Level: Int, FlagValue {
    case low = 1
    case high = 2
}
