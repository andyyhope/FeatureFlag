import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// A published schema is flat by design. The editor needs the shape back so a deep tree
/// can be walked a screen at a time.
final class FlagTreeNodeTests: XCTestCase {

    private var tree: FlagTreeNode { FlagTreeNode(schema: FlagSchema(TreeFlags.self)) }

    func testRootHoldsOnlyItsOwnFlags() {
        XCTAssertEqual(tree.flags.map(\.key), ["top", "second"])
    }

    func testRootListsItsDirectGroupsOnly() {
        XCTAssertEqual(tree.groups.map(\.title), ["Checkout"])
    }

    func testAGroupHoldsItsOwnFlagsAndItsOwnSubgroups() throws {
        let checkout = try XCTUnwrap(tree.groups.first)

        XCTAssertEqual(checkout.path, ["checkout"])
        XCTAssertEqual(checkout.flags.map(\.key), ["checkout.apple-pay"])
        XCTAssertEqual(checkout.groups.map(\.title), ["Express"])
    }

    func testNestingGoesAsDeepAsTheContainer() throws {
        let express = try XCTUnwrap(tree.groups.first?.groups.first)
        XCTAssertEqual(express.path, ["checkout", "express"])
        XCTAssertEqual(express.flags.map(\.key), ["checkout.express.one-tap"])

        let deeper = try XCTUnwrap(express.groups.first)
        XCTAssertEqual(deeper.path, ["checkout", "express", "confirmation"])
        XCTAssertEqual(deeper.flags.map(\.key), ["checkout.express.confirmation.delay"])
        XCTAssertTrue(deeper.groups.isEmpty)
    }

    func testEveryFlagAppearsExactlyOnceInTheWholeTree() {
        let all = tree.allFlags.map(\.key)
        XCTAssertEqual(Set(all).count, all.count, "a flag is in two places")
        XCTAssertEqual(Set(all), Set(FlagSchema(TreeFlags.self).flags.map(\.key)))
    }

    func testDeclarationOrderSurvives() {
        XCTAssertEqual(
            tree.allFlags.map(\.key),
            [
                "top", "second", "checkout.apple-pay",
                "checkout.express.one-tap", "checkout.express.confirmation.delay",
            ]
        )
    }

    func testIdentityIsThePath() {
        XCTAssertEqual(tree.id, "")
        XCTAssertEqual(tree.groups.first?.id, "checkout")
        XCTAssertEqual(tree.groups.first?.groups.first?.id, "checkout.express")
    }

    // MARK: - Degenerate shapes

    func testAnEmptySchemaProducesAnEmptyRoot() {
        let empty = FlagTreeNode(schema: FlagSchema(flags: []))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.flags.isEmpty)
        XCTAssertTrue(empty.groups.isEmpty)
    }

    func testAGroupWithNoFlagsOfItsOwnStillCarriesItsChildren() {
        // "Checkout" holding only "Express" must not vanish, or its contents become
        // unreachable.
        let schema = FlagSchema(
            flags: [entry(key: "checkout.express.one-tap", path: ["checkout", "express", "oneTap"])],
            groups: [
                FlagSchema.Group(propertyPath: ["checkout"], description: "Checkout"),
                FlagSchema.Group(propertyPath: ["checkout", "express"], description: "Express"),
            ]
        )
        let node = FlagTreeNode(schema: schema)

        XCTAssertEqual(node.groups.map(\.title), ["Checkout"])
        XCTAssertTrue(node.groups[0].flags.isEmpty)
        XCTAssertEqual(node.groups[0].groups.map(\.title), ["Express"])
        XCTAssertEqual(node.allFlags.count, 1)
        XCTAssertFalse(node.isEmpty)
    }

    func testAGroupDeclaredWithNoFlagsAnywhereIsEmpty() {
        let schema = FlagSchema(
            flags: [],
            groups: [FlagSchema.Group(propertyPath: ["hollow"], description: "Hollow")]
        )
        XCTAssertTrue(FlagTreeNode(schema: schema).isEmpty)
    }

    private func entry(key: FlagKey, path: [String]) -> FlagSchema.Entry {
        FlagSchema.Entry(
            key: key, propertyPath: path, description: "",
            valueType: .bool, defaultValue: .bool(false)
        )
    }
}

// MARK: - Fixtures

@FlagContainer
private struct TreeFlags {
    @Flag(default: false, description: "Top") var top: Bool
    @Flag(default: 1, description: "Second") var second: Int
    @FlagGroup(description: "Checkout") var checkout: TreeCheckoutFlags
}

@FlagContainer
private struct TreeCheckoutFlags {
    @Flag(default: false, description: "Apple Pay") var applePay: Bool
    @FlagGroup(description: "Express") var express: TreeExpressFlags
}

@FlagContainer
private struct TreeExpressFlags {
    @Flag(default: false, description: "One tap") var oneTap: Bool
    @FlagGroup(description: "Confirmation") var confirmation: TreeConfirmationFlags
}

@FlagContainer
private struct TreeConfirmationFlags {
    @Flag(default: 3.0, description: "Delay") var delay: Double
}
