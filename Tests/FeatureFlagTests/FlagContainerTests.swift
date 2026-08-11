import XCTest

@testable import FeatureFlag

/// The containers here are written by hand. That is deliberate: this file is the
/// specification for what the `@FlagContainer` macro must generate in Phase 1c.
final class FlagContainerTests: XCTestCase {

    // MARK: - Reading values

    func testFlagFallsBackToItsDefaultWhenNothingIsStored() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertFalse(flags.newOnboarding)
    }

    func testFlagReadsAStoredValue() {
        let lookup = StubLookup(boxes: ["new-onboarding": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.newOnboarding)
    }

    func testFlagFallsBackToItsDefaultWhenTheStoredValueIsTheWrongType() {
        let lookup = StubLookup(boxes: ["max-items": .string("nonsense")])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertEqual(flags.maxItems, 10)
    }

    func testUnboundFlagReturnsItsDefault() {
        // A flag declared outside any container still reads, which keeps previews and
        // unit tests from needing a tower.
        let flag = Flag(default: 7, description: "Detached")
        XCTAssertEqual(flag.wrappedValue, 7)
    }

    // MARK: - Nesting

    func testNestedGroupNamespacesItsKeys() {
        let lookup = StubLookup(boxes: ["checkout.apple-pay": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.applePay)
    }

    func testDeeplyNestedGroupNamespacesItsKeys() {
        let lookup = StubLookup(boxes: ["checkout.express.one-tap": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.express.oneTap)
    }

    func testChildValueIsIndependentOfItsParent() {
        // Nesting is namespacing only: no gating, no inheritance.
        let lookup = StubLookup(boxes: ["checkout.express.one-tap": .bool(true)])
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.express.oneTap)
        XCTAssertFalse(flags.checkout.applePay)
    }

    // MARK: - Key encoding

    func testKeyEncodingComesFromTheLookup() {
        let lookup = StubLookup(
            keyEncoding: .snakecase,
            boxes: ["checkout.apple_pay": .bool(true)]
        )
        let flags = AppFlags(_lookup: lookup, _keyPrefix: .root)
        XCTAssertTrue(flags.checkout.applePay)
    }

    // MARK: - Projected accessor

    func testProjectedValueExposesTheResolvedKey() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertEqual(flags.$newOnboarding.key, "new-onboarding")
        XCTAssertEqual(flags.checkout.express.$oneTap.key, "checkout.express.one-tap")
    }

    func testProjectedValueExposesDeclarationMetadata() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertEqual(flags.$newOnboarding.description, "New onboarding")
        XCTAssertEqual(flags.$newOnboarding.defaultValue, false)
        XCTAssertEqual(flags.$newOnboarding.remoteKey, "featureToggles.onboarding.v2")
    }

    func testProjectedValueReportsNoRemoteKeyWhenUndeclared() {
        let flags = AppFlags(_lookup: StubLookup(), _keyPrefix: .root)
        XCTAssertNil(flags.$maxItems.remoteKey)
    }

    // MARK: - Descriptors

    func testDescriptorsListFlagsInDeclarationOrder() {
        let names = AppFlags.flagDescriptors.map(\.propertyName)
        XCTAssertEqual(names, ["newOnboarding", "maxItems", "checkout"])
    }

    func testFlagDescriptorCarriesEverythingAnEditorNeeds() {
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

    func testGroupDescriptorRerootsItsChildrenUnderItsOwnPath() {
        guard case let .group(group) = AppFlags.flagDescriptors[2] else {
            return XCTFail("expected a group")
        }
        XCTAssertEqual(group.propertyName, "checkout")
        XCTAssertEqual(group.description, "Checkout")

        guard case let .flag(applePay) = group.children[0] else {
            return XCTFail("expected a flag")
        }
        XCTAssertEqual(applePay.keyPath, FlagKeyPath(["checkout", "applePay"]))
    }

    func testDescriptorsRerootThroughMoreThanOneLevel() {
        guard case let .group(checkout) = AppFlags.flagDescriptors[2],
              case let .group(express) = checkout.children[1],
              case let .flag(oneTap) = express.children[0]
        else {
            return XCTFail("expected checkout.express.oneTap")
        }
        XCTAssertEqual(oneTap.keyPath, FlagKeyPath(["checkout", "express", "oneTap"]))
    }

    func testEnumDescriptorListsItsCases() {
        guard case let .group(checkout) = AppFlags.flagDescriptors[2],
              case let .flag(tier) = checkout.children[2]
        else {
            return XCTFail("expected checkout.tier")
        }
        XCTAssertEqual(tier.valueType, .string)
        XCTAssertEqual(tier.cases, [.string("free"), .string("pro")])
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
}

private struct AppFlags: FlagContainer {

    @Flag(default: false, description: "New onboarding", remoteKey: "featureToggles.onboarding.v2")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Maximum items")
    var maxItems: Int

    var checkout: CheckoutFlags

    init(_lookup: any FlagLookup, _keyPrefix: FlagKeyPath) {
        _newOnboarding = Flag(
            default: false,
            description: "New onboarding",
            remoteKey: "featureToggles.onboarding.v2",
            lookup: _lookup,
            keyPath: _keyPrefix.appending("newOnboarding")
        )
        _maxItems = Flag(
            default: 10,
            description: "Maximum items",
            lookup: _lookup,
            keyPath: _keyPrefix.appending("maxItems")
        )
        checkout = CheckoutFlags(_lookup: _lookup, _keyPrefix: _keyPrefix.appending("checkout"))
    }

    static var flagDescriptors: [FlagSchemaNode] {
        [
            .flag(
                FlagDescriptor(
                    propertyName: "newOnboarding",
                    keyPath: FlagKeyPath(["newOnboarding"]),
                    description: "New onboarding",
                    valueType: Bool.flagValueType,
                    defaultValue: (false as Bool).box,
                    cases: _flagValueCases(of: Bool.self),
                    remoteKey: "featureToggles.onboarding.v2"
                )
            ),
            .flag(
                FlagDescriptor(
                    propertyName: "maxItems",
                    keyPath: FlagKeyPath(["maxItems"]),
                    description: "Maximum items",
                    valueType: Int.flagValueType,
                    defaultValue: (10 as Int).box,
                    cases: _flagValueCases(of: Int.self),
                    remoteKey: nil
                )
            ),
            .group(
                FlagGroupDescriptor(
                    propertyName: "checkout",
                    keyPath: FlagKeyPath(["checkout"]),
                    description: "Checkout",
                    children: CheckoutFlags.flagDescriptors.map { $0.prefixed(by: "checkout") }
                )
            ),
        ]
    }
}

private struct CheckoutFlags: FlagContainer {

    @Flag(default: false, description: "Apple Pay")
    var applePay: Bool

    var express: ExpressFlags

    @Flag(default: Tier.free, description: "Tier")
    var tier: Tier

    init(_lookup: any FlagLookup, _keyPrefix: FlagKeyPath) {
        _applePay = Flag(
            default: false,
            description: "Apple Pay",
            lookup: _lookup,
            keyPath: _keyPrefix.appending("applePay")
        )
        express = ExpressFlags(_lookup: _lookup, _keyPrefix: _keyPrefix.appending("express"))
        _tier = Flag(
            default: Tier.free,
            description: "Tier",
            lookup: _lookup,
            keyPath: _keyPrefix.appending("tier")
        )
    }

    static var flagDescriptors: [FlagSchemaNode] {
        [
            .flag(
                FlagDescriptor(
                    propertyName: "applePay",
                    keyPath: FlagKeyPath(["applePay"]),
                    description: "Apple Pay",
                    valueType: Bool.flagValueType,
                    defaultValue: (false as Bool).box,
                    cases: _flagValueCases(of: Bool.self),
                    remoteKey: nil
                )
            ),
            .group(
                FlagGroupDescriptor(
                    propertyName: "express",
                    keyPath: FlagKeyPath(["express"]),
                    description: "Express",
                    children: ExpressFlags.flagDescriptors.map { $0.prefixed(by: "express") }
                )
            ),
            .flag(
                FlagDescriptor(
                    propertyName: "tier",
                    keyPath: FlagKeyPath(["tier"]),
                    description: "Tier",
                    valueType: Tier.flagValueType,
                    defaultValue: (Tier.free as Tier).box,
                    cases: _flagValueCases(of: Tier.self),
                    remoteKey: nil
                )
            ),
        ]
    }
}

private struct ExpressFlags: FlagContainer {

    @Flag(default: false, description: "One tap")
    var oneTap: Bool

    init(_lookup: any FlagLookup, _keyPrefix: FlagKeyPath) {
        _oneTap = Flag(
            default: false,
            description: "One tap",
            lookup: _lookup,
            keyPath: _keyPrefix.appending("oneTap")
        )
    }

    static var flagDescriptors: [FlagSchemaNode] {
        [
            .flag(
                FlagDescriptor(
                    propertyName: "oneTap",
                    keyPath: FlagKeyPath(["oneTap"]),
                    description: "One tap",
                    valueType: Bool.flagValueType,
                    defaultValue: (false as Bool).box,
                    cases: _flagValueCases(of: Bool.self),
                    remoteKey: nil
                )
            )
        ]
    }
}

private final class StubLookup: FlagLookup, @unchecked Sendable {

    let keyEncoding: KeyEncoding
    private let boxes: [FlagKey: FlagValueBox]

    init(keyEncoding: KeyEncoding = .kebabcase, boxes: [FlagKey: FlagValueBox] = [:]) {
        self.keyEncoding = keyEncoding
        self.boxes = boxes
    }

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        boxes[key]
    }
}
