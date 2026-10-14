import XCTest

import FeatureFlag

/// A host app with feature flags is very likely to call one of its own types
/// `FeatureFlag` — an enum of flag names is the obvious thing to write. Inside that
/// module the type then shadows the *module* name, so any generated reference spelled
/// `FeatureFlag.Something` is looked up as a member of the host's enum and fails.
///
/// The file-scope type below recreates that. This file only compiles if no macro
/// expansion spells a reference through the module name.
final class ModuleNameShadowingTests: XCTestCase {

    func testContainerMacrosSurviveAHostTypeNamedFeatureFlag() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "checkout.apple-pay")

        let pole = FlagPole(ModuleShadowedFlags.self, sources: [local])

        XCTAssertEqual(pole.flags.title, "none")
        XCTAssertTrue(pole.flags.checkout.applePay)
        XCTAssertEqual(pole.flags.endpoints.values, [ModuleShadowedEndpoint(name: "prod", weight: 1)])
    }

    func testDescriptorsSurviveAHostTypeNamedFeatureFlag() {
        XCTAssertEqual(
            ModuleShadowedFlags.flagDescriptors.map(\.propertyName),
            ["title", "endpoints", "checkout"]
        )
        XCTAssertEqual(ModuleShadowedEndpoint.flagRecordShape.map(\.name), ["name", "weight"])
    }

    func testTheLocalTypeReallyDoesShadowTheModule() {
        // Guards the guard: if this stopped shadowing, the tests above prove nothing.
        XCTAssertEqual(FeatureFlag.allCases, [.newOnboarding])
    }
}

// MARK: - Hostile local declaration

private enum FeatureFlag: CaseIterable {
    case newOnboarding
}

// MARK: - Fixtures

@FlagContainer(description: "Flags in a module that owns a FeatureFlag type")
private struct ModuleShadowedFlags {

    @Flag(default: "none", description: "Title")
    var title: String

    @Flag(default: [ModuleShadowedEndpoint(name: "prod", weight: 1)], description: "Endpoints")
    var endpoints: FlagRecords<ModuleShadowedEndpoint>

    @FlagGroup(description: "Checkout")
    var checkout: ModuleShadowedCheckoutFlags
}

@FlagContainer
private struct ModuleShadowedCheckoutFlags {

    @Flag(default: false, description: "Apple Pay")
    var applePay: Bool
}

@FlagRecord
private struct ModuleShadowedEndpoint: Equatable {
    @FlagRecordKey var name: String
    var weight: Int
}
