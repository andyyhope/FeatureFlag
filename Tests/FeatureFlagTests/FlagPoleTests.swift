import Combine
import XCTest

@testable import FeatureFlag

final class FlagPoleTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Resolution

    func testReadsTheCompiledDefaultWhenNoSourceHasAValue() {
        let tower = FlagPole(DemoFlags.self, sources: [])
        XCTAssertFalse(tower.flags.newOnboarding)
        XCTAssertEqual(tower.flags.maxItems, 10)
    }

    func testReadsFromASource() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "new-onboarding")

        let tower = FlagPole(DemoFlags.self, sources: [local])
        XCTAssertTrue(tower.flags.newOnboarding)
    }

    func testLocalOverrideBeatsRemote() throws {
        // The precedence that makes the companion app trustworthy: a value set by hand
        // stays set until it is explicitly cleared.
        let local = SnapshotSource(name: "local")
        let remote = SnapshotSource(name: "remote")
        try remote.setBox(.bool(true), for: "new-onboarding")
        try local.setBox(.bool(false), for: "new-onboarding")

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        XCTAssertFalse(tower.flags.newOnboarding)
    }

    func testRemoteAppliesWhereThereIsNoLocalOverride() throws {
        let local = SnapshotSource(name: "local")
        let remote = SnapshotSource(name: "remote")
        try remote.setBox(.int(3), for: "max-items")
        try local.setBox(.bool(true), for: "new-onboarding")

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        XCTAssertEqual(tower.flags.maxItems, 3)
        XCTAssertTrue(tower.flags.newOnboarding)
    }

    func testFallsThroughWhenTheHighestSourceHoldsTheWrongType() throws {
        let local = SnapshotSource(name: "local")
        let remote = SnapshotSource(name: "remote")
        try local.setBox(.string("nonsense"), for: "max-items")
        try remote.setBox(.int(3), for: "max-items")

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        XCTAssertEqual(tower.flags.maxItems, 3)
    }

    func testNestedFlagsResolveThroughTheTower() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "checkout.express.one-tap")

        let tower = FlagPole(DemoFlags.self, sources: [local])
        XCTAssertTrue(tower.flags.checkout.express.oneTap)
    }

    func testDynamicMemberLookupReadsFlagsWithoutGoingThroughFlags() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.int(4), for: "max-items")

        let tower = FlagPole(DemoFlags.self, sources: [local])
        XCTAssertEqual(tower.maxItems, 4)
        XCTAssertTrue(tower.checkout.express.oneTap == false)
    }

    func testKeyEncodingIsConfigurable() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "checkout.apple_pay")

        let tower = FlagPole(DemoFlags.self, sources: [local], keyEncoding: .snakecase)
        XCTAssertTrue(tower.flags.checkout.applePay)
    }

    // MARK: - Explaining a value

    func testResolutionNamesTheWinningSource() throws {
        let local = SnapshotSource(name: "local")
        let remote = SnapshotSource(name: "remote")
        try remote.setBox(.bool(true), for: "new-onboarding")

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        let resolution = tower.resolution(for: tower.flags.$newOnboarding)

        XCTAssertEqual(resolution.sourceName, "remote")
        XCTAssertEqual(resolution.box, .bool(true))
    }

    func testResolutionReportsTheCompiledDefault() {
        let tower = FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])
        let resolution = tower.resolution(for: tower.flags.$newOnboarding)

        XCTAssertNil(resolution.sourceName)
        XCTAssertEqual(resolution.box, .bool(false))
    }

    func testResolutionSkipsASourceHoldingTheWrongType() throws {
        let local = SnapshotSource(name: "local")
        let remote = SnapshotSource(name: "remote")
        try local.setBox(.string("nonsense"), for: "max-items")
        try remote.setBox(.int(3), for: "max-items")

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        XCTAssertEqual(tower.resolution(for: tower.flags.$maxItems).sourceName, "remote")
    }

    // MARK: - Overrides

    func testOverridesListsOnlyFlagsSomeSourceSupplies() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "new-onboarding")
        try local.setBox(.bool(true), for: "checkout.apple-pay")

        let tower = FlagPole(DemoFlags.self, sources: [local])
        XCTAssertEqual(
            tower.overrides,
            ["new-onboarding": .bool(true), "checkout.apple-pay": .bool(true)]
        )
    }

    func testOverridesIsEmptyWhenEverythingIsDefault() {
        let tower = FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])
        XCTAssertTrue(tower.overrides.isEmpty)
    }

    func testSettingAnOverrideThroughTheAccessorTakesEffect() throws {
        let local = SnapshotSource(name: "local")
        let tower = FlagPole(DemoFlags.self, sources: [local])

        try tower.setOverride(true, for: tower.flags.$newOnboarding)
        XCTAssertTrue(tower.flags.newOnboarding)
    }

    func testRemovingAnOverrideRestoresTheDefault() throws {
        let local = SnapshotSource(name: "local")
        let tower = FlagPole(DemoFlags.self, sources: [local])

        try tower.setOverride(true, for: tower.flags.$newOnboarding)
        try tower.removeOverride(for: tower.flags.$newOnboarding)
        XCTAssertFalse(tower.flags.newOnboarding)
    }

    func testRemoveAllOverridesTouchesOnlyKnownFlags() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "new-onboarding")
        try local.setBox(.string("unrelated"), for: "someone-elses-key")

        let tower = FlagPole(DemoFlags.self, sources: [local])
        try tower.removeAllOverrides()

        XCTAssertFalse(tower.flags.newOnboarding)
        XCTAssertEqual(local.box(for: "someone-elses-key", as: .string), .string("unrelated"))
    }

    // MARK: - Combine

    func testObjectWillChangeFiresWhenASourceChanges() throws {
        let local = SnapshotSource(name: "local")
        let tower = FlagPole(DemoFlags.self, sources: [local])

        let fired = expectation(description: "objectWillChange")
        tower.objectWillChange
            .sink { _ in fired.fulfill() }
            .store(in: &cancellables)

        try local.setBox(.bool(true), for: "new-onboarding")
        wait(for: [fired], timeout: 2)
    }

    func testFlagPublisherEmitsTheCurrentValueImmediately() {
        let tower = FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])

        var received: [Bool] = []
        tower.flags.$newOnboarding.publisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received, [false])
    }

    func testFlagPublisherEmitsOnChange() throws {
        let local = SnapshotSource(name: "local")
        let tower = FlagPole(DemoFlags.self, sources: [local])

        var received: [Bool] = []
        tower.flags.$newOnboarding.publisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        try local.setBox(.bool(true), for: "new-onboarding")
        XCTAssertEqual(received, [false, true])
    }

    func testFlagPublisherIgnoresUnrelatedKeys() throws {
        let local = SnapshotSource(name: "local")
        let tower = FlagPole(DemoFlags.self, sources: [local])

        var received: [Bool] = []
        tower.flags.$newOnboarding.publisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        try local.setBox(.int(5), for: "max-items")
        XCTAssertEqual(received, [false])
    }
}
