import XCTest

@testable import FeatureFlag

final class FlagValueTypeTests: XCTestCase {

    // MARK: - Names

    func testEveryPrimitiveHasAName() {
        let expected: [(FlagValueType, String)] = [
            (.bool, "bool"), (.int, "int"), (.double, "double"), (.float, "float"),
            (.string, "string"), (.data, "data"), (.date, "date"), (.url, "url"),
        ]
        for (type, name) in expected {
            XCTAssertEqual(type.typeName, name)
        }
    }

    func testCollectionNamesCarryTheirElementType() {
        XCTAssertEqual(FlagValueType.array(.string).typeName, "array<string>")
        XCTAssertEqual(FlagValueType.dictionary(.int).typeName, "dictionary<int>")
    }

    func testNestedCollectionNamesNest() {
        XCTAssertEqual(
            FlagValueType.array(.dictionary(.array(.bool))).typeName,
            "array<dictionary<array<bool>>>"
        )
    }

    // MARK: - Parsing

    func testEveryNameRoundTrips() {
        let types: [FlagValueType] = [
            .bool, .int, .double, .float, .string, .data, .date, .url,
            .array(.string), .dictionary(.int),
            .array(.array(.bool)), .dictionary(.dictionary(.date)),
            .array(.dictionary(.array(.url))),
        ]
        for type in types {
            XCTAssertEqual(FlagValueType(typeName: type.typeName), type, "failed for \(type)")
        }
    }

    func testUnknownNamesAreRejected() {
        for name in ["", "banana", "Bool", "INT", "array", "dictionary"] {
            XCTAssertNil(FlagValueType(typeName: name), "should reject \(name)")
        }
    }

    func testMalformedCollectionNamesAreRejected() {
        for name in [
            "array<>", "array<banana>", "array<int", "array int>",
            "dictionary<>", "dictionary<banana>", "array<<int>>",
        ] {
            XCTAssertNil(FlagValueType(typeName: name), "should reject \(name)")
        }
    }

    // MARK: - Matching

    func testABoxMatchesItsOwnType() {
        XCTAssertTrue(FlagValueBox.bool(true).matches(.bool))
        XCTAssertTrue(FlagValueBox.int(1).matches(.int))
        XCTAssertTrue(FlagValueBox.url(URL(string: "https://a.example")!).matches(.url))
    }

    func testABoxDoesNotMatchAnotherType() {
        XCTAssertFalse(FlagValueBox.int(1).matches(.bool))
        XCTAssertFalse(FlagValueBox.double(1).matches(.int))
        XCTAssertFalse(FlagValueBox.string("a").matches(.url))
    }

    func testAnEmptyCollectionMatchesAnyCollectionOfThatShape() {
        // Nothing in an empty array contradicts the declared element type.
        XCTAssertTrue(FlagValueBox.array([]).matches(.array(.bool)))
        XCTAssertTrue(FlagValueBox.array([]).matches(.array(.dictionary(.int))))
        XCTAssertTrue(FlagValueBox.dictionary([:]).matches(.dictionary(.string)))
    }

    func testACollectionDoesNotMatchAScalar() {
        XCTAssertFalse(FlagValueBox.array([.bool(true)]).matches(.bool))
        XCTAssertFalse(FlagValueBox.bool(true).matches(.array(.bool)))
        XCTAssertFalse(FlagValueBox.array([.bool(true)]).matches(.dictionary(.bool)))
    }

    func testOneWrongElementFailsTheWholeCollection() {
        XCTAssertFalse(FlagValueBox.array([.int(1), .string("a")]).matches(.array(.int)))
        XCTAssertFalse(
            FlagValueBox.dictionary(["a": .int(1), "b": .bool(true)]).matches(.dictionary(.int))
        )
    }

    func testNestedCollectionsAreCheckedAllTheWayDown() {
        XCTAssertTrue(
            FlagValueBox.array([.array([.int(1)])]).matches(.array(.array(.int)))
        )
        XCTAssertFalse(
            FlagValueBox.array([.array([.string("a")])]).matches(.array(.array(.int)))
        )
    }
}
