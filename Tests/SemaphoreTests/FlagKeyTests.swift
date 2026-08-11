import XCTest

@testable import Semaphore

/// Keys are derived, not stored. The macro records raw Swift property names, and the
/// encoding configured on the tower turns a path into the string a source sees. That
/// split is what lets compile-time metadata coexist with runtime key configuration.
final class FlagKeyTests: XCTestCase {

    // MARK: - Paths

    func testRootPathIsEmpty() {
        XCTAssertEqual(FlagKeyPath.root.propertyNames, [])
    }

    func testAppendingBuildsAPath() {
        let path = FlagKeyPath.root.appending("checkout").appending("applePay")
        XCTAssertEqual(path.propertyNames, ["checkout", "applePay"])
    }

    func testAppendingDoesNotMutateTheOriginal() {
        let base = FlagKeyPath.root.appending("checkout")
        _ = base.appending("applePay")
        XCTAssertEqual(base.propertyNames, ["checkout"])
    }

    // MARK: - Kebab-case encoding

    func testKebabcaseSeparatesCamelCaseWords() {
        XCTAssertEqual(kebab("newOnboarding"), "new-onboarding")
    }

    func testKebabcaseLeavesLowercaseNamesAlone() {
        XCTAssertEqual(kebab("checkout"), "checkout")
    }

    func testKebabcaseLowercasesTrailingAcronyms() {
        XCTAssertEqual(kebab("enableAPI"), "enable-api")
    }

    func testKebabcaseSplitsAcronymFollowedByWord() {
        XCTAssertEqual(kebab("apiKey"), "api-key")
        XCTAssertEqual(kebab("useHTTPSOnly"), "use-https-only")
    }

    func testKebabcaseKeepsDigitsAttachedToTheirWord() {
        XCTAssertEqual(kebab("checkoutV2"), "checkout-v2")
    }

    func testKebabcaseJoinsNestedComponentsWithADot() {
        let path = FlagKeyPath.root
            .appending("checkout")
            .appending("express")
            .appending("oneTap")
        XCTAssertEqual(KeyEncoding.kebabcase.key(for: path), "checkout.express.one-tap")
    }

    // MARK: - Other encodings

    func testSnakecaseUsesUnderscoresWithinComponents() {
        let path = FlagKeyPath.root.appending("checkout").appending("applePay")
        XCTAssertEqual(KeyEncoding.snakecase.key(for: path), "checkout.apple_pay")
    }

    func testVerbatimPreservesPropertyNames() {
        let path = FlagKeyPath.root.appending("checkout").appending("applePay")
        XCTAssertEqual(KeyEncoding.verbatim.key(for: path), "checkout.applePay")
    }

    func testCustomSeparatorIsHonoured() {
        let encoding = KeyEncoding(separator: "/", transform: { $0 })
        let path = FlagKeyPath.root.appending("checkout").appending("applePay")
        XCTAssertEqual(encoding.key(for: path), "checkout/applePay")
    }

    // MARK: - Keys

    func testKeyIsExpressibleByStringLiteral() {
        let key: FlagKey = "checkout.apple-pay"
        XCTAssertEqual(key.rawValue, "checkout.apple-pay")
    }

    func testKeyDescribesItselfAsItsRawValue() {
        XCTAssertEqual(String(describing: FlagKey("checkout.apple-pay")), "checkout.apple-pay")
    }

    func testKeyCodesAsAPlainString() throws {
        let encoded = try JSONEncoder().encode(["key": FlagKey("checkout.apple-pay")])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"key":"checkout.apple-pay"}"#)
    }

    // MARK: - Helpers

    private func kebab(_ propertyName: String) -> String {
        KeyEncoding.kebabcase.key(for: FlagKeyPath.root.appending(propertyName)).rawValue
    }
}
