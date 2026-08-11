import XCTest

@testable import FeatureFlag

final class KeyEncodingEdgeCaseTests: XCTestCase {

    private func kebab(_ name: String) -> String {
        KeyEncoding.kebabcase.key(for: FlagKeyPath([name])).rawValue
    }

    // MARK: - Word splitting

    func testSplittingHandlesASingleLetter() {
        XCTAssertEqual(KeyEncoding.splitWords("a"), ["a"])
        XCTAssertEqual(KeyEncoding.splitWords("A"), ["A"])
    }

    func testSplittingHandlesAnEmptyName() {
        XCTAssertEqual(KeyEncoding.splitWords(""), [])
    }

    func testSplittingHandlesAnAllCapsName() {
        XCTAssertEqual(KeyEncoding.splitWords("API"), ["API"])
        XCTAssertEqual(kebab("API"), "api")
    }

    func testSplittingHandlesLeadingCapital() {
        XCTAssertEqual(kebab("NewOnboarding"), "new-onboarding")
    }

    func testSplittingKeepsRunsOfDigitsWithTheirWord() {
        XCTAssertEqual(kebab("v2Enabled"), "v2-enabled")
        XCTAssertEqual(kebab("enable2FA"), "enable2-fa")
    }

    func testSplittingHandlesUnderscoresInPropertyNames() {
        XCTAssertEqual(kebab("legacy_name"), "legacy_name")
    }

    // MARK: - Paths

    func testAnEmptyPathEncodesToAnEmptyKey() {
        XCTAssertEqual(KeyEncoding.kebabcase.key(for: .root), "")
    }

    func testASingleComponentPathHasNoSeparator() {
        XCTAssertEqual(KeyEncoding.kebabcase.key(for: FlagKeyPath(["oneTap"])), "one-tap")
    }

    func testPrependingPutsAComponentAtTheFront() {
        let path = FlagKeyPath(["express", "oneTap"]).prepending("checkout")
        XCTAssertEqual(path.propertyNames, ["checkout", "express", "oneTap"])
    }

    func testPrependingDoesNotMutateTheOriginal() {
        let base = FlagKeyPath(["oneTap"])
        _ = base.prepending("checkout")
        XCTAssertEqual(base.propertyNames, ["oneTap"])
    }

    // MARK: - Custom encodings

    func testACustomTransformIsAppliedToEveryComponent() {
        let encoding = KeyEncoding { $0.uppercased() }
        XCTAssertEqual(encoding.key(for: FlagKeyPath(["checkout", "applePay"])), "CHECKOUT.APPLEPAY")
    }

    func testAnEmptySeparatorJoinsComponentsDirectly() {
        let encoding = KeyEncoding(separator: "") { $0 }
        XCTAssertEqual(encoding.key(for: FlagKeyPath(["a", "b"])), "ab")
    }

    func testAMultiCharacterSeparatorIsUsedWhole() {
        let encoding = KeyEncoding(separator: "::") { $0 }
        XCTAssertEqual(encoding.key(for: FlagKeyPath(["a", "b"])), "a::b")
    }

    // MARK: - Keys

    func testKeysAreValueTypesForDictionaryUse() {
        var storage: [FlagKey: Int] = [:]
        storage[FlagKey("a.b")] = 1
        XCTAssertEqual(storage["a.b"], 1)
        XCTAssertEqual(FlagKey("a.b"), "a.b")
        XCTAssertNotEqual(FlagKey("a.b"), "a.c")
    }

    func testKeysDecodeFromPlainStrings() throws {
        let decoded = try JSONDecoder().decode([FlagKey].self, from: Data(#"["a.b","c"]"#.utf8))
        XCTAssertEqual(decoded, ["a.b", "c"])
    }
}
