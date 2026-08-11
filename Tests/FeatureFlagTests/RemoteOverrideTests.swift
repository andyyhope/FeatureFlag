import XCTest

@testable import FeatureFlag

/// Remote payloads come from a backend with its own shape, so flags declare where they
/// live with `remoteKey` and the framework only decodes — it never fetches.
final class RemoteOverrideTests: XCTestCase {

    private func makeSource() -> RemoteOverrideSource {
        RemoteOverrideSource(DemoFlags.self)
    }

    private func json(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Dot paths

    func testResolvesNestedDotPaths() throws {
        let source = makeSource()
        _ = try source.apply(
            json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#),
            format: .json
        )
        XCTAssertEqual(source.box(for: "new-onboarding", as: .bool), .bool(true))
    }

    func testResolvesArrayIndicesInAPath() throws {
        let source = RemoteOverrideSource(IndexedFlags.self)
        _ = try source.apply(
            json(#"{"experiments": [{"enabled": false}, {"enabled": true}]}"#),
            format: .json
        )
        XCTAssertEqual(source.box(for: "second-experiment", as: .bool), .bool(true))
    }

    func testFlagsWithoutARemoteKeyAreNeverRemotelyOverridable() throws {
        let source = makeSource()
        _ = try source.apply(json(#"{"max-items": 99, "maxItems": 99}"#), format: .json)
        XCTAssertNil(source.box(for: "max-items", as: .int))
    }

    func testAbsentPathsAreReportedAndLeftAlone() throws {
        let source = makeSource()
        let result = try source.apply(
            json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#),
            format: .json
        )

        XCTAssertEqual(result.appliedKeys, ["new-onboarding"])
        XCTAssertEqual(result.absentKeys, ["checkout.apple-pay"])
        XCTAssertNil(source.box(for: "checkout.apple-pay", as: .bool))
    }

    func testApplyingANewPayloadReplacesTheOldOne() throws {
        let source = makeSource()
        _ = try source.apply(json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#), format: .json)
        _ = try source.apply(json(#"{"featureToggles": {"checkout": {"applePay": true}}}"#), format: .json)

        XCTAssertNil(source.box(for: "new-onboarding", as: .bool))
        XCTAssertEqual(source.box(for: "checkout.apple-pay", as: .bool), .bool(true))
    }

    func testClearingRemovesEverything() throws {
        let source = makeSource()
        _ = try source.apply(json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#), format: .json)
        source.clear()
        XCTAssertNil(source.box(for: "new-onboarding", as: .bool))
    }

    // MARK: - Strict typing

    func testRejectsAStringForABooleanAndAppliesNothing() throws {
        let source = makeSource()
        let payload = json(
            #"{"featureToggles": {"onboarding": {"v2": "true"}, "checkout": {"applePay": true}}}"#
        )

        XCTAssertThrowsError(try source.apply(payload, format: .json)) { error in
            XCTAssertEqual(
                error as? RemoteOverrideError,
                .rejected([
                    RemoteOverrideProblem(
                        key: "new-onboarding",
                        remoteKey: "featureToggles.onboarding.v2",
                        kind: .typeMismatch
                    )
                ])
            )
        }
        XCTAssertNil(source.box(for: "checkout.apple-pay", as: .bool))
    }

    func testRejectsANumberForABoolean() throws {
        let source = makeSource()
        let payload = json(#"{"featureToggles": {"onboarding": {"v2": 1}}}"#)

        XCTAssertThrowsError(try source.apply(payload, format: .json))
    }

    func testAcceptsAWholeNumberForADoubleFlag() throws {
        // JSON has one number type, so a backend sending 1 for a Double flag is an
        // artefact of the format rather than a type error. Widening is exact.
        let source = RemoteOverrideSource(NumericFlags.self)
        _ = try source.apply(json(#"{"cfg": {"ratio": 1}}"#), format: .json)
        XCTAssertEqual(source.box(for: "ratio", as: .double), .double(1))
    }

    func testRejectsAFractionalNumberForAnIntegerFlag() {
        let source = RemoteOverrideSource(NumericFlags.self)
        XCTAssertThrowsError(try source.apply(json(#"{"cfg": {"count": 1.5}}"#), format: .json))
    }

    func testRejectsAValueOutsideAnEnumsCases() throws {
        let source = RemoteOverrideSource(EnumFlags.self)
        let payload = json(#"{"cfg": {"tier": "enterprise"}}"#)

        XCTAssertThrowsError(try source.apply(payload, format: .json)) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownCase])
        }
    }

    func testAcceptsAValidEnumCase() throws {
        let source = RemoteOverrideSource(EnumFlags.self)
        _ = try source.apply(json(#"{"cfg": {"tier": "pro"}}"#), format: .json)
        XCTAssertEqual(source.box(for: "tier", as: .string), .string("pro"))
    }

    func testReportsEveryProblemAtOnce() {
        let source = RemoteOverrideSource(NumericFlags.self)
        let payload = json(#"{"cfg": {"count": 1.5, "ratio": "lots"}}"#)

        XCTAssertThrowsError(try source.apply(payload, format: .json)) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected")
            }
            XCTAssertEqual(Set(problems.map(\.key)), ["count", "ratio"])
        }
    }

    func testRejectsMalformedData() {
        XCTAssertThrowsError(try makeSource().apply(json("not json"), format: .json)) { error in
            guard case .malformed = error as? RemoteOverrideError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    // MARK: - PLIST

    func testAcceptsAPropertyListPayload() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["featureToggles": ["onboarding": ["v2": true]]],
            format: .xml,
            options: 0
        )
        let source = makeSource()
        _ = try source.apply(plist, format: .plist)
        XCTAssertEqual(source.box(for: "new-onboarding", as: .bool), .bool(true))
    }

    // MARK: - Custom mappers

    func testACustomMapperCanReshapeAnAwkwardPayload() throws {
        let source = RemoteOverrideSource(DemoFlags.self, mapper: RecordListMapper())
        _ = try source.apply(
            json(#"{"flags": [{"name": "new-onboarding", "value": true}]}"#),
            format: .json
        )
        XCTAssertEqual(source.box(for: "new-onboarding", as: .bool), .bool(true))
    }

    // MARK: - Precedence

    func testALocalOverrideBeatsARemotePayload() throws {
        let local = SnapshotSource(name: "local")
        let remote = makeSource()
        _ = try remote.apply(json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#), format: .json)

        let tower = FlagPole(DemoFlags.self, sources: [local, remote])
        XCTAssertTrue(tower.flags.newOnboarding)

        try local.setBox(.bool(false), for: "new-onboarding")
        XCTAssertFalse(tower.flags.newOnboarding)
        XCTAssertEqual(tower.resolution(for: tower.flags.$newOnboarding).sourceName, "local")
    }

    func testApplyingAPayloadNotifiesTheTower() throws {
        let remote = makeSource()
        let tower = FlagPole(DemoFlags.self, sources: [remote])

        let changed = expectation(description: "objectWillChange")
        let cancellable = tower.objectWillChange.sink { _ in changed.fulfill() }
        defer { cancellable.cancel() }

        _ = try remote.apply(json(#"{"featureToggles": {"onboarding": {"v2": true}}}"#), format: .json)
        wait(for: [changed], timeout: 2)
    }
}

// MARK: - Fixtures

@FlagContainer
private struct IndexedFlags {

    @Flag(default: false, description: "Second experiment", remoteKey: "experiments.1.enabled")
    var secondExperiment: Bool
}

@FlagContainer
private struct NumericFlags {

    @Flag(default: 0, description: "Count", remoteKey: "cfg.count")
    var count: Int

    @Flag(default: 0.0, description: "Ratio", remoteKey: "cfg.ratio")
    var ratio: Double
}

@FlagContainer
private struct EnumFlags {

    @Flag(default: DemoTier.free, description: "Tier", remoteKey: "cfg.tier")
    var tier: DemoTier
}

/// A backend that sends a list of records rather than a nested object.
private struct RecordListMapper: RemoteOverrideMapper {

    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        guard case let .array(records)? = value.value(atPath: "flags") else { return [:] }

        var result = [FlagKey: RemoteValue]()
        for record in records {
            guard
                case let .string(name)? = record.value(atPath: "name"),
                let value = record.value(atPath: "value")
            else { continue }
            result[FlagKey(name)] = value
        }
        return result
    }
}
