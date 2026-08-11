import XCTest

@testable import Semaphore

/// Behavioural counterpart to `FlagContainerTests`: identical expectations, but the
/// conformance is generated rather than hand-written. If these two files ever
/// disagree, the macro is wrong.
final class FlagContainerMacroTests: XCTestCase {

    // MARK: - Reading values

    func testGeneratedContainerFallsBackToDefaults() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertFalse(flags.newOnboarding)
        XCTAssertEqual(flags.maxItems, 10)
    }

    func testGeneratedContainerReadsStoredValues() {
        let lookup = StubLookup(boxes: ["new-onboarding": .bool(true), "max-items": .int(3)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.newOnboarding)
        XCTAssertEqual(flags.maxItems, 3)
    }

    // MARK: - Nesting

    func testGeneratedGroupNamespacesItsKeys() {
        let lookup = StubLookup(boxes: ["checkout.apple-pay": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.applePay)
    }

    func testGeneratedContainerNamespacesThroughThreeLevels() {
        let lookup = StubLookup(boxes: ["checkout.express.one-tap": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.express.oneTap)
    }

    func testGeneratedContainerHonoursTheLookupKeyEncoding() {
        let lookup = StubLookup(
            keyEncoding: .snakecase,
            boxes: ["checkout.apple_pay": .bool(true)]
        )
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.applePay)
    }

    // MARK: - Projection

    func testGeneratedContainerProjectsAccessors() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertEqual(flags.$newOnboarding.key, "new-onboarding")
        XCTAssertEqual(flags.$newOnboarding.description, "New onboarding")
        XCTAssertEqual(flags.$newOnboarding.remoteKey, "featureToggles.onboarding.v2")
        XCTAssertNil(flags.$maxItems.remoteKey)
        XCTAssertEqual(flags.checkout.express.$oneTap.key, "checkout.express.one-tap")
    }

    // MARK: - Descriptors

    func testGeneratedDescriptorsPreserveDeclarationOrder() {
        XCTAssertEqual(
            AppFlags.flagDescriptors.map(\.propertyName),
            ["newOnboarding", "maxItems", "checkout"]
        )
    }

    func testGeneratedFlagDescriptorIsComplete() {
        guard case let .flag(descriptor) = AppFlags.flagDescriptors[0] else {
            return XCTFail("expected a flag")
        }
        XCTAssertEqual(descriptor.propertyName, "newOnboarding")
        XCTAssertEqual(descriptor.keyPath, FlagKeyPath(["newOnboarding"]))
        XCTAssertEqual(descriptor.description, "New onboarding")
        XCTAssertEqual(descriptor.valueType, .bool)
        XCTAssertEqual(descriptor.defaultValue, .bool(false))
        XCTAssertEqual(descriptor.remoteKey, "featureToggles.onboarding.v2")
        XCTAssertNil(descriptor.cases)
    }

    func testGeneratedGroupDescriptorRerootsChildren() {
        guard case let .group(checkout) = AppFlags.flagDescriptors[2] else {
            return XCTFail("expected a group")
        }
        XCTAssertEqual(checkout.description, "Checkout")

        guard case let .group(express) = checkout.children[1],
              case let .flag(oneTap) = express.children[0]
        else {
            return XCTFail("expected checkout.express.oneTap")
        }
        XCTAssertEqual(oneTap.keyPath, FlagKeyPath(["checkout", "express", "oneTap"]))
    }

    func testGeneratedDescriptorListsEnumCases() {
        guard case let .group(checkout) = AppFlags.flagDescriptors[2],
              case let .flag(tier) = checkout.children[2]
        else {
            return XCTFail("expected checkout.tier")
        }
        XCTAssertEqual(tier.valueType, .string)
        XCTAssertEqual(tier.cases, [.string("free"), .string("pro")])
    }

    // MARK: - Declarations the macro must leave alone

    func testGeneratedContainerIgnoresComputedAndInitialisedProperties() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertEqual(flags.notAFlag, "plain")
        XCTAssertEqual(flags.derived, "plain/10")
        XCTAssertEqual(AppFlags.flagDescriptors.count, 3)
    }

}

// MARK: - Fixtures

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
}

@FlagContainer
private struct AppFlags {

    @Flag(default: false, description: "New onboarding", remoteKey: "featureToggles.onboarding.v2")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Maximum items")
    var maxItems: Int

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags

    let notAFlag = "plain"

    var derived: String { "\(notAFlag)/\(maxItems)" }
}

@FlagContainer
private struct CheckoutFlags {

    @Flag(default: false, description: "Apple Pay")
    var applePay: Bool

    @FlagGroup(description: "Express")
    var express: ExpressFlags

    @Flag(default: Tier.free, description: "Tier")
    var tier: Tier
}

@FlagContainer
private struct ExpressFlags {

    @Flag(default: false, description: "One tap")
    var oneTap: Bool
}

private final class StubLookup: FlagLookup, @unchecked Sendable {

    let keyEncoding: KeyEncoding
    private let boxes: [FlagKey: FlagValueBox]

    init(keyEncoding: KeyEncoding = .kebabcase, boxes: [FlagKey: FlagValueBox] = [:]) {
        self.keyEncoding = keyEncoding
        self.boxes = boxes
    }

    func box(for key: FlagKey) -> FlagValueBox? {
        boxes[key]
    }
}
