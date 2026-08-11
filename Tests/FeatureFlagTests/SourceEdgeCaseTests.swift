import Combine
import XCTest

@testable import FeatureFlag

final class SourceEdgeCaseTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - FlagChange

    func testAWholesaleChangeAffectsEveryKey() {
        XCTAssertTrue(FlagChange.all.affects("anything"))
    }

    func testAKeyedChangeAffectsOnlyItsKeys() {
        let change = FlagChange.keys(["a", "b"])
        XCTAssertTrue(change.affects("a"))
        XCTAssertFalse(change.affects("c"))
    }

    func testAnEmptyKeyedChangeAffectsNothing() {
        XCTAssertFalse(FlagChange.keys([]).affects("a"))
    }

    // MARK: - SnapshotSource

    func testASnapshotCanBeSeededAtInit() {
        let source = SnapshotSource(name: "seed", values: ["a": .int(1)])
        XCTAssertEqual(source.box(for: "a", as: .int), .int(1))
    }

    func testWritingTheSameValueAgainEmitsNothing() throws {
        // Otherwise every idle write would wake every subscriber and redraw SwiftUI.
        let source = SnapshotSource(name: "local")
        try source.setBox(.int(1), for: "a")

        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        try source.setBox(.int(1), for: "a")
        XCTAssertTrue(changes.isEmpty)

        try source.setBox(.int(2), for: "a")
        XCTAssertEqual(changes, [.keys(["a"])])
    }

    func testRemovingAValueEmitsAChange() throws {
        let source = SnapshotSource(name: "local")
        try source.setBox(.int(1), for: "a")

        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        try source.setBox(nil, for: "a")
        XCTAssertEqual(changes, [.keys(["a"])])
        XCTAssertNil(source.box(for: "a", as: .int))
    }

    func testRemovingSomethingAbsentEmitsNothing() throws {
        let source = SnapshotSource(name: "local")
        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        try source.setBox(nil, for: "absent")
        XCTAssertTrue(changes.isEmpty)
    }

    func testReplacingEverythingReportsOneWholesaleChange() {
        let source = SnapshotSource(name: "local", values: ["a": .int(1)])
        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        source.replaceAll(with: ["b": .int(2)])

        XCTAssertEqual(changes, [.all])
        XCTAssertNil(source.box(for: "a", as: .int))
        XCTAssertEqual(source.box(for: "b", as: .int), .int(2))
    }

    func testASnapshotIsSafeUnderConcurrentWrites() {
        let source = SnapshotSource(name: "local")
        let finished = expectation(description: "writes")
        finished.expectedFulfillmentCount = 200

        for index in 0 ..< 200 {
            DispatchQueue.global().async {
                try? source.setBox(.int(index), for: FlagKey("key.\(index % 8)"))
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(source.values.count, 8)
    }

    // MARK: - UserDefaultsSource

    func testAnAppGroupSourceIsNilWhenTheGroupIsUnavailable() {
        // UserDefaults refuses its own bundle identifier as a suite name, which stands
        // in here for an App Group missing from the entitlements.
        let identifier = Bundle.main.bundleIdentifier ?? "xctest"
        XCTAssertNil(UserDefaultsSource(appGroup: identifier))
    }

    func testAnAppGroupSourceNamesItselfForDiagnostics() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let source = try XCTUnwrap(UserDefaultsSource(appGroup: suite, name: "Companion"))
        XCTAssertEqual(source.sourceName, "Companion")
    }

    func testEmptyCollectionsRoundTripThroughUserDefaults() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "local")

        try source.setBox(.array([]), for: "empty.array")
        try source.setBox(.dictionary([:]), for: "empty.dictionary")

        XCTAssertEqual(source.box(for: "empty.array", as: .array(.string)), .array([]))
        XCTAssertEqual(
            source.box(for: "empty.dictionary", as: .dictionary(.int)), .dictionary([:])
        )
    }

    func testAPartlyWrongCollectionIsRejectedWhole() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "local")

        defaults.set([1, "two"], forKey: "mixed")
        XCTAssertNil(source.box(for: "mixed", as: .array(.int)))
    }

    func testAnInvalidStoredURLIsRejected() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "local")

        defaults.set(42, forKey: "not.a.url")
        XCTAssertNil(source.box(for: "not.a.url", as: .url))
    }

    // MARK: - Resolution

    func testAnEmptySourceStackAlwaysReportsTheDefault() {
        let resolver = FlagResolver(sources: [], keyEncoding: .kebabcase)
        let resolution = resolver.resolution(for: "anything", as: .bool)

        XCTAssertTrue(resolution.isDefault)
        XCTAssertNil(resolution.sourceName)
        XCTAssertNil(resolution.box)
    }

    func testResolutionWalksPastEverySourceThatCannotAnswer() throws {
        let first = SnapshotSource(name: "first")
        let second = SnapshotSource(name: "second")
        let third = SnapshotSource(name: "third")
        try third.setBox(.int(3), for: "max-items")

        let resolver = FlagResolver(sources: [first, second, third], keyEncoding: .kebabcase)
        XCTAssertEqual(resolver.resolution(for: "max-items", as: .int).sourceName, "third")
    }
}
