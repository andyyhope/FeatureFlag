import XCTest

@testable import FeatureFlag

/// Shapes of container that a real codebase produces sooner or later.
final class MacroEdgeCaseTests: XCTestCase {

    private let lookup = EdgeCaseLookup()

    // MARK: - Unusual container shapes

    func testAContainerWithNoFlagsAtAllWorks() {
        let flags = NoFlags(_lookup: lookup, _keyPrefix: .root)
        _ = flags
        XCTAssertTrue(NoFlags.flagDescriptors.isEmpty)
    }

    func testAContainerOfNothingButGroupsWorks() {
        XCTAssertEqual(GroupsOnlyFlags.flagDescriptors.count, 1)
        XCTAssertEqual(GroupsOnlyFlags.flagDescriptors.flattened().map(\.propertyName), ["oneTap"])

        let flags = GroupsOnlyFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.express.$oneTap.key, "express.one-tap")
    }

    func testDeeplyNestedGroupsKeepNesting() {
        let flags = DeepFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.a.b.c.$deep.key, "a.b.c.deep")
        XCTAssertEqual(
            DeepFlags.flagDescriptors.flattened().map(\.keyPath.propertyNames),
            [["a", "b", "c", "deep"]]
        )
    }

    func testTheSameGroupTypeCanBeMountedTwice() {
        // Descriptors are re-rooted per mount point, so one type in two places must not
        // report the same key twice.
        let flags = TwiceFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.first.$oneTap.key, "first.one-tap")
        XCTAssertEqual(flags.second.$oneTap.key, "second.one-tap")

        let keys = TwiceFlags.flagDescriptors.flattened().map { KeyEncoding.kebabcase.key(for: $0.keyPath) }
        XCTAssertEqual(keys, ["first.one-tap", "second.one-tap"])
    }

    // MARK: - Awkward declarations

    func testComplexDefaultExpressionsAreCarriedThrough() {
        let flags = ComplexDefaultsFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.computedDefault, 6)
        XCTAssertEqual(flags.listDefault, ["a", "b"])
        XCTAssertEqual(flags.mapDefault, ["x": 1])
        XCTAssertEqual(flags.nestedDefault, [["a"]])
    }

    func testComplexDefaultsAppearInDescriptors() {
        let descriptors = ComplexDefaultsFlags.flagDescriptors.flattened()
        XCTAssertEqual(descriptors.first { $0.propertyName == "computedDefault" }?.defaultValue, .int(6))
        XCTAssertEqual(
            descriptors.first { $0.propertyName == "nestedDefault" }?.valueType,
            .array(.array(.string))
        )
    }

    func testFullyQualifiedValueTypesWork() {
        let flags = QualifiedFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.$stamp.key, "stamp")
        XCTAssertEqual(QualifiedFlags.flagDescriptors.flattened().first?.valueType, .date)
    }

    func testNonFlagMembersAreLeftEntirelyAlone() {
        let flags = MixedFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.constant, 5)
        XCTAssertEqual(flags.computed, 10)
        XCTAssertEqual(MixedFlags.staticValue, "static")
        XCTAssertEqual(flags.method(), 15)
        XCTAssertEqual(MixedFlags.flagDescriptors.count, 1)
    }
}

// MARK: - Fixtures

@FlagContainer
private struct NoFlags {}

@FlagContainer
private struct GroupsOnlyFlags {
    @FlagGroup(description: "Express")
    var express: OneTapFlags
}

@FlagContainer
private struct OneTapFlags {
    @Flag(default: false, description: "One tap")
    var oneTap: Bool
}

@FlagContainer
private struct TwiceFlags {
    @FlagGroup(description: "First")
    var first: OneTapFlags

    @FlagGroup(description: "Second")
    var second: OneTapFlags
}

@FlagContainer
private struct DeepFlags {
    @FlagGroup(description: "A")
    var a: DeepB
}

@FlagContainer
private struct DeepB {
    @FlagGroup(description: "B")
    var b: DeepC
}

@FlagContainer
private struct DeepC {
    @FlagGroup(description: "C")
    var c: DeepD
}

@FlagContainer
private struct DeepD {
    @Flag(default: false, description: "Deep")
    var deep: Bool
}

private func makeDefault() -> Int { 6 }

@FlagContainer
private struct ComplexDefaultsFlags {

    @Flag(default: makeDefault(), description: "From a function")
    var computedDefault: Int

    @Flag(default: ["a", "b"], description: "From an array literal")
    var listDefault: [String]

    @Flag(default: ["x": 1], description: "From a dictionary literal")
    var mapDefault: [String: Int]

    @Flag(default: [["a"]], description: "From a nested literal")
    var nestedDefault: [[String]]
}

@FlagContainer
private struct QualifiedFlags {

    @Flag(default: Foundation.Date(timeIntervalSince1970: 0), description: "Stamp")
    var stamp: Foundation.Date
}

@FlagContainer
private struct MixedFlags {

    @Flag(default: false, description: "Only flag")
    var onlyFlag: Bool

    let constant = 5
    var computed: Int { constant * 2 }
    static let staticValue = "static"
    func method() -> Int { constant * 3 }
}

private final class EdgeCaseLookup: FlagLookup, @unchecked Sendable {
    let keyEncoding: KeyEncoding = .kebabcase
    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? { nil }
}
