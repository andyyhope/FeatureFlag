import XCTest

@testable import FeatureFlag

/// A host app that has feature flags is very likely to declare its own `Flag` type.
/// Every name that generated code touches is shadowed below by a deliberately useless
/// local type, so this file fails to compile if the macro ever emits an unqualified
/// reference.
///
/// File-scope `private` shadows module-level names within this file only, which keeps
/// the simulation faithful without disturbing the rest of the suite.
///
/// Note the asymmetry. Names only generated code mentions are fully protected by
/// qualification. `Flag` is different: it is an attribute the *host* writes, and a
/// local `Flag` type makes `@Flag` fail with "struct 'Flag' cannot be used as an
/// attribute" before any macro runs. The workaround is to qualify the attribute, which
/// is what this file does and what the documentation must say.
final class ShadowingTests: XCTestCase {

    func testMacroExpansionSurvivesShadowedTypeNames() {
        let lookup = ShadowStubLookup(boxes: ["checkout.apple-pay": .bool(true)])
        let flags = ShadowedFlags(_lookup: lookup, _keyPrefix: .root)

        XCTAssertTrue(flags.checkout.applePay)
        XCTAssertEqual(flags.$title.key, "title")
    }

    func testDescriptorsSurviveShadowedTypeNames() {
        XCTAssertEqual(ShadowedFlags.flagDescriptors.map(\.propertyName), ["title", "checkout"])

        guard case let .group(checkout) = ShadowedFlags.flagDescriptors[1],
              case let .flag(applePay) = checkout.children[0]
        else {
            return XCTFail("expected checkout.applePay")
        }
        XCTAssertEqual(applePay.keyPath, FeatureFlag.FlagKeyPath(["checkout", "applePay"]))
    }

    func testLocalTypesReallyDoShadowTheModule() {
        // Guards the guard: if these stopped shadowing, the tests above prove nothing.
        XCTAssertFalse((Flag.self as Any.Type) is FeatureFlag.Flag<Bool>.Type)
        XCTAssertFalse((FlagKeyPath.self as Any.Type) is FeatureFlag.FlagKeyPath.Type)
        XCTAssertFalse((FlagSchemaNode.self as Any.Type) is FeatureFlag.FlagSchemaNode.Type)
    }
}

// MARK: - Hostile local declarations

private struct Flag {}
private struct FlagKey {}
private struct FlagKeyPath {}
private struct FlagValueBox {}
private struct FlagDescriptor {}
private struct FlagGroupDescriptor {}
private struct FlagSchemaNode {}
private protocol FlagLookup {}
private func _flagValueCases(of type: Any.Type) -> Never { fatalError() }

// MARK: - Fixtures

@FlagContainer
private struct ShadowedFlags {

    @FeatureFlag.Flag(default: "none", description: "Title")
    var title: String

    @FlagGroup(description: "Checkout")
    var checkout: ShadowedCheckoutFlags
}

@FlagContainer
private struct ShadowedCheckoutFlags {

    @FeatureFlag.Flag(default: false, description: "Apple Pay")
    var applePay: Bool
}

private final class ShadowStubLookup: FeatureFlag.FlagLookup, @unchecked Sendable {

    let keyEncoding: KeyEncoding = .kebabcase
    private let boxes: [FeatureFlag.FlagKey: FeatureFlag.FlagValueBox]

    init(boxes: [FeatureFlag.FlagKey: FeatureFlag.FlagValueBox]) {
        self.boxes = boxes
    }

    func box(for key: FeatureFlag.FlagKey) -> FeatureFlag.FlagValueBox? {
        boxes[key]
    }
}
