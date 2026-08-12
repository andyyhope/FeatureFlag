import Combine
import XCTest

@testable import FeatureFlag

final class FlagPoleEdgeCaseTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Writing with nothing to write to

    func testSettingAnOverrideWithNoMutableSourceReports() {
        let pole = FlagPole(DemoFlags.self, sources: [])
        XCTAssertThrowsError(try pole.setOverride(true, for: pole.flags.$newOnboarding)) { error in
            XCTAssertEqual(error as? FlagError, .noMutableSource)
        }
    }

    func testSettingAnOverrideWithOnlyAReadOnlySourceReports() throws {
        let remote = RemoteOverrideSource(DemoFlags.self)
        let pole = FlagPole(DemoFlags.self, sources: [remote])
        XCTAssertThrowsError(try pole.setOverride(true, for: pole.flags.$newOnboarding)) { error in
            XCTAssertEqual(error as? FlagError, .noMutableSource)
        }
    }

    func testWritesGoToTheHighestPriorityMutableSource() throws {
        let top = SnapshotSource(name: "top")
        let bottom = SnapshotSource(name: "bottom")
        let pole = FlagPole(DemoFlags.self, sources: [top, bottom])

        try pole.setOverride(true, for: pole.flags.$newOnboarding)

        XCTAssertEqual(top.values["new-onboarding"], .bool(true))
        XCTAssertNil(bottom.values["new-onboarding"])
    }

    func testWritesSkipAReadOnlySourceAboveAMutableOne() throws {
        let remote = RemoteOverrideSource(DemoFlags.self)
        let local = SnapshotSource(name: "local")
        let pole = FlagPole(DemoFlags.self, sources: [remote, local])

        try pole.setOverride(true, for: pole.flags.$newOnboarding)
        XCTAssertEqual(local.values["new-onboarding"], .bool(true))
    }

    // MARK: - Describing the tree

    func testDescriptorsAreFlattenedDepthFirst() {
        let pole = FlagPole(DemoFlags.self, sources: [])
        XCTAssertEqual(
            pole.descriptors.map(\.propertyName),
            ["newOnboarding", "maxItems", "applePay", "oneTap", "tier"]
        )
    }

    func testFlattenedDescriptorsKeepTheirFullKeyPaths() {
        let pole = FlagPole(DemoFlags.self, sources: [])
        XCTAssertEqual(
            pole.descriptors.map(\.keyPath.propertyNames),
            [
                ["newOnboarding"],
                ["maxItems"],
                ["checkout", "applePay"],
                ["checkout", "express", "oneTap"],
                ["checkout", "tier"],
            ]
        )
    }

    func testKeysMatchTheConfiguredEncoding() {
        let kebab = FlagPole(DemoFlags.self, sources: [])
        let snake = FlagPole(DemoFlags.self, sources: [], keyEncoding: .snakecase)

        XCTAssertTrue(kebab.keys.contains("checkout.apple-pay"))
        XCTAssertTrue(snake.keys.contains("checkout.apple_pay"))
    }

    func testEveryDeclaredFlagAppearsExactlyOnce() {
        let pole = FlagPole(DemoFlags.self, sources: [])
        XCTAssertEqual(Set(pole.keys).count, pole.keys.count)
        XCTAssertEqual(pole.keys.count, 5)
    }

    // MARK: - Clearing

    func testRemoveAllOverridesOnlyClearsTheTopMutableSource() throws {
        // Documented behaviour: writes go to one source, so clearing does too. A value
        // sitting in a lower source is not an override this pole put there.
        let top = SnapshotSource(name: "top")
        let bottom = SnapshotSource(name: "bottom")
        try top.setBox(.bool(true), for: "new-onboarding")
        try bottom.setBox(.int(3), for: "max-items")

        let pole = FlagPole(DemoFlags.self, sources: [top, bottom])
        try pole.removeAllOverrides()

        XCTAssertTrue(top.values.isEmpty)
        XCTAssertEqual(bottom.values["max-items"], .int(3))
    }

    // MARK: - Reading concurrently

    func testReadingFromManyThreadsAtOnceIsSafe() throws {
        // Apps read flags off the main thread constantly, so this must not trip the
        // resolver's lock or tear a value.
        let local = SnapshotSource(name: "local")
        try local.setBox(.int(42), for: "max-items")
        let pole = FlagPole(DemoFlags.self, sources: [local])

        let finished = expectation(description: "reads")
        finished.expectedFulfillmentCount = 200

        for _ in 0 ..< 200 {
            DispatchQueue.global().async {
                XCTAssertEqual(pole.flags.maxItems, 42)
                XCTAssertFalse(pole.flags.checkout.express.oneTap)
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 20)
    }

    func testReadingWhileAnotherThreadWritesIsSafe() throws {
        let local = SnapshotSource(name: "local")
        let pole = FlagPole(DemoFlags.self, sources: [local])

        let finished = expectation(description: "mixed")
        finished.expectedFulfillmentCount = 200

        for index in 0 ..< 200 {
            DispatchQueue.global().async {
                if index.isMultiple(of: 2) {
                    try? local.setBox(.int(index), for: "max-items")
                } else {
                    _ = pole.flags.maxItems
                }
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 20)
    }

    // MARK: - Detached flags

    func testADetachedFlagPublishesItsDefaultAndNothingElse() {
        let flag = Flag(default: 7, description: "Detached")

        var received: [Int] = []
        flag.projectedValue.publisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received, [7])
        XCTAssertEqual(flag.projectedValue.currentValue, 7)
    }

    // MARK: - Default lookup behaviour

    func testAMinimalLookupNeedsOnlyTwoMembers() {
        // Previews and tests should not have to implement change publishing or writing.
        let lookup = MinimalLookup()
        let flags = DemoFlags(_lookup: lookup, _keyPrefix: .root)

        XCTAssertEqual(flags.maxItems, 99)
        XCTAssertThrowsError(try lookup.setOverride(.int(1), for: "max-items")) { error in
            XCTAssertEqual(error as? FlagError, .noMutableSource)
        }
    }

    func testAMinimalLookupNeverEmitsChanges() {
        let lookup = MinimalLookup()
        var received = 0
        lookup.changePublisher(for: "max-items")
            .sink { _ in received += 1 }
            .store(in: &cancellables)
        XCTAssertEqual(received, 0)
    }
}

private final class MinimalLookup: FlagLookup, @unchecked Sendable {
    let keyEncoding: KeyEncoding = .kebabcase

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        key == "max-items" ? .int(99) : nil
    }
}

extension FlagPoleEdgeCaseTests {

    func testResolutionByKeyMatchesTheTypedForm() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.bool(true), for: "new-onboarding")
        let pole = FlagPole(DemoFlags.self, sources: [local])

        let typed = pole.resolution(for: pole.flags.$newOnboarding)
        let byKey = pole.resolution(for: "new-onboarding", as: .bool)

        XCTAssertEqual(byKey, typed)
        XCTAssertEqual(byKey.sourceName, "local")
    }

    func testResolutionByKeyFillsInTheCompiledDefault() {
        let pole = FlagPole(DemoFlags.self, sources: [])
        let resolution = pole.resolution(for: "max-items", as: .int)

        XCTAssertTrue(resolution.isDefault)
        XCTAssertEqual(resolution.box, .int(10), "should report the value in effect")
    }

    func testEveryFlagCanBeExplainedInALoop() {
        // The point of the key-based form: a diagnostics screen over the whole schema.
        let pole = FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])
        let explained = pole.schema.flags.map { pole.resolution(for: $0.key, as: $0.valueType) }

        XCTAssertEqual(explained.count, 5)
        XCTAssertTrue(explained.allSatisfy { $0.box != nil }, "every flag has a value in effect")
    }
}
