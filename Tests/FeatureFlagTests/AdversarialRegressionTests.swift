import Combine
import XCTest

@testable import FeatureFlag

/// Regressions for defects found by attacking the framework rather than exercising it.
final class AdversarialRegressionTests: XCTestCase {

    // MARK: - Non-finite numbers used to kill the process

    func testExportingAnInfiniteDoubleThrowsRatherThanCrashing() throws {
        // JSONSerialization raises an Objective-C exception for infinity, which no
        // Swift `try` can catch — the process would die mid-export.
        let local = SnapshotSource(name: "local")
        try local.setBox(.double(.infinity), for: "ratio")
        let pole = FlagPole(EdgeFlags.self, sources: [local])

        XCTAssertThrowsError(try pole.export(as: .json)) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("ratio"))
        }
    }

    func testExportingANaNThrows() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.double(.nan), for: "ratio")
        let pole = FlagPole(EdgeFlags.self, sources: [local])

        XCTAssertThrowsError(try pole.export(as: .json))
    }

    func testANonFiniteNumberNestedInACollectionIsCaught() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.array([.double(1), .double(.infinity)]), for: "ratios")
        let pole = FlagPole(EdgeFlags.self, sources: [local])

        XCTAssertThrowsError(try pole.export(as: .json)) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("ratios"))
        }
    }

    func testAQRCodeOfANonFiniteNumberThrows() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.double(.infinity), for: "ratio")
        let pole = FlagPole(EdgeFlags.self, sources: [local])

        XCTAssertThrowsError(try pole.qrCodeString())
    }

    func testASchemaWithANonFiniteDefaultThrows() {
        let schema = FlagSchema(
            flags: [
                FlagSchema.Entry(
                    key: "ratio",
                    propertyPath: ["ratio"],
                    description: "",
                    valueType: .double,
                    defaultValue: .double(.infinity)
                )
            ]
        )
        XCTAssertThrowsError(try schema.jsonData()) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("ratio"))
        }
    }

    func testFiniteNumbersAreUnaffected() throws {
        let local = SnapshotSource(name: "local")
        try local.setBox(.double(1.5), for: "ratio")
        let pole = FlagPole(EdgeFlags.self, sources: [local])
        XCTAssertNoThrow(try pole.export(as: .json))
    }

    func testDetectionLooksAllTheWayIntoNestedCollections() {
        XCTAssertTrue(FlagValueBox.double(.infinity).containsNonFiniteNumber)
        XCTAssertTrue(FlagValueBox.float(.nan).containsNonFiniteNumber)
        XCTAssertTrue(FlagValueBox.array([.array([.double(.nan)])]).containsNonFiniteNumber)
        XCTAssertTrue(FlagValueBox.dictionary(["a": .double(.infinity)]).containsNonFiniteNumber)
        XCTAssertFalse(FlagValueBox.array([.double(1), .int(2)]).containsNonFiniteNumber)
        XCTAssertFalse(FlagValueBox.string("infinity").containsNonFiniteNumber)
    }

    // MARK: - A mapper's typo used to vanish

    func testAMapperKeyNoFlagHasIsReportedNotIgnored() {
        // Silently doing nothing looks exactly like a backend that sent no overrides,
        // which is the hardest kind of integration bug to find.
        let source = RemoteOverrideSource(EdgeFlags.self, mapper: TypoMapper())

        XCTAssertThrowsError(try source.apply(Data(#"{"a": 1}"#.utf8), format: .json)) { error in
            XCTAssertEqual(
                error as? RemoteOverrideError,
                .rejected([
                    RemoteOverrideProblem(key: "rat1o", remoteKey: "rat1o", kind: .unknownFlag)
                ])
            )
        }
    }

    func testTheBuiltInMapperCannotProduceThatProblem() throws {
        // DotPathMapper only emits keys it read from the schema.
        let source = RemoteOverrideSource(EdgeFlags.self)
        XCTAssertNoThrow(try source.apply(Data(#"{"cfg": {"ratio": 1.5}}"#.utf8), format: .json))
    }

    // MARK: - Import used to apply part of a payload

    func testAWriteFailingPartwayUndoesTheRest() throws {
        let source = RefusingSource(refusing: "enabled")
        let pole = FlagPole(EdgeFlags.self, sources: [source])

        let json = #"{"formatVersion":1,"values":{"ratio":1.5,"enabled":true}}"#
        XCTAssertThrowsError(try pole.importPayload(Data(json.utf8), as: .json))

        XCTAssertTrue(source.storedKeys.isEmpty, "left behind: \(source.storedKeys)")
        XCTAssertEqual(pole.flags.ratio, 0)
        XCTAssertFalse(pole.flags.enabled)
    }

    func testRollbackRestoresAPreviousOverrideRatherThanClearingIt() throws {
        let source = RefusingSource(refusing: "enabled")
        try source.setBox(.double(9.5), for: "ratio")

        let pole = FlagPole(EdgeFlags.self, sources: [source])
        let json = #"{"formatVersion":1,"values":{"ratio":1.5,"enabled":false}}"#
        XCTAssertThrowsError(try pole.importPayload(Data(json.utf8), as: .json))

        XCTAssertEqual(pole.flags.ratio, 9.5, "the earlier override should be restored, not cleared")
    }

    func testRollbackIsBestEffortWhenTheSourceRefusesEverything() throws {
        // A store that has run out of room refuses the undo as well. Nothing can be
        // done about that, and pretending otherwise would be worse than saying so.
        let source = RefusingSource(refusing: "enabled", refusingEverythingAfterwards: true)
        let pole = FlagPole(EdgeFlags.self, sources: [source])

        let json = #"{"formatVersion":1,"values":{"ratio":1.5,"enabled":true}}"#
        XCTAssertThrowsError(try pole.importPayload(Data(json.utf8), as: .json))
        XCTAssertTrue(pole.flags.ratio == 1.5 || pole.flags.ratio == 0)
    }

    func testASuccessfulImportStillAppliesEverything() throws {
        let pole = FlagPole(EdgeFlags.self, sources: [SnapshotSource(name: "local")])
        let json = #"{"formatVersion":1,"values":{"ratio":1.5,"enabled":true}}"#

        let result = try pole.importPayload(Data(json.utf8), as: .json)
        XCTAssertEqual(result.appliedKeys, ["enabled", "ratio"])
        XCTAssertEqual(pole.flags.ratio, 1.5)
        XCTAssertTrue(pole.flags.enabled)
    }
}

// MARK: - Fixtures

@FlagContainer
private struct EdgeFlags {

    @Flag(default: 0.0, description: "Ratio", remoteKey: "cfg.ratio")
    var ratio: Double

    @Flag(default: false, description: "Enabled")
    var enabled: Bool

    @Flag(default: [], description: "Ratios")
    var ratios: [Double]
}

private struct TypoMapper: RemoteOverrideMapper {
    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        ["rat1o": .double(2.5)]
    }
}

/// Refuses one particular key, standing in for a store that cannot represent a value.
/// Optionally refuses everything from then on, standing in for one that has died.
private final class RefusingSource: MutableFlagValueSource, @unchecked Sendable {

    let sourceName = "refusing"

    private let refusedKey: FlagKey
    private let refusesEverythingAfterwards: Bool
    private let lock = NSLock()
    private var values: [FlagKey: FlagValueBox] = [:]
    private var hasRefused = false

    init(refusing refusedKey: FlagKey, refusingEverythingAfterwards: Bool = false) {
        self.refusedKey = refusedKey
        self.refusesEverythingAfterwards = refusingEverythingAfterwards
    }

    var storedKeys: [FlagKey] {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.sorted { $0.rawValue < $1.rawValue }
    }

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    var changes: AnyPublisher<FlagChange, Never> { Empty().eraseToAnyPublisher() }

    func setBox(_ box: FlagValueBox?, for key: FlagKey) throws {
        lock.lock()
        defer { lock.unlock() }

        if refusesEverythingAfterwards, hasRefused {
            throw FlagError.unsupportedValue(key)
        }
        if key == refusedKey, box != nil {
            hasRefused = true
            throw FlagError.unsupportedValue(key)
        }
        values[key] = box
    }
}

// MARK: - Bulk operations used to storm the other process

final class WriteAmplificationTests: XCTestCase {

    func testClearingEverythingOnlyWritesWhatWasSet() throws {
        // Blindly writing nil to every declared flag turns one reset into hundreds of
        // cross-process broadcasts, each waking the other app to re-read everything.
        let source = CountingSource()
        let pole = FlagPole(ManyEdgeFlags.self, sources: [source])
        try pole.setOverride(true, for: pole.flags.$a)

        source.writes = 0
        try pole.removeAllOverrides()

        XCTAssertEqual(source.writes, 1, "should touch only the one flag that was set")
        XCTAssertTrue(pole.overrides.isEmpty)
    }

    func testClearingNothingWritesNothing() throws {
        let source = CountingSource()
        let pole = FlagPole(ManyEdgeFlags.self, sources: [source])

        try pole.removeAllOverrides()
        XCTAssertEqual(source.writes, 0)
    }

    func testUserDefaultsIgnoresAWriteThatChangesNothing() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "shared")

        try source.setBox(.bool(true), for: "a")

        var changes = 0
        let cancellable = source.changes.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        try source.setBox(.bool(true), for: "a")
        XCTAssertEqual(changes, 0, "an identical write should not announce a change")

        try source.setBox(.bool(false), for: "a")
        XCTAssertEqual(changes, 1)
    }

    func testRemovingSomethingAbsentFromUserDefaultsAnnouncesNothing() throws {
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "shared")

        var changes = 0
        let cancellable = source.changes.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        try source.setBox(nil, for: "never.set")
        XCTAssertEqual(changes, 0)
    }

    func testAFlagChangingTypeIsStillRewritten() throws {
        // NSNumber equates 1 and true, so a naive equality check would treat this as a
        // no-op and leave the old value in place.
        let suite = "com.featureflag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UserDefaultsSource(defaults: defaults, name: "shared")

        try source.setBox(.int(1), for: "a")

        var changes = 0
        let cancellable = source.changes.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        try source.setBox(.bool(true), for: "a")
        XCTAssertEqual(changes, 1, "1 and true are different values, however NSNumber compares them")
    }
}

@FlagContainer
private struct ManyEdgeFlags {
    @Flag(default: false, description: "a") var a: Bool
    @Flag(default: false, description: "b") var b: Bool
    @Flag(default: false, description: "c") var c: Bool
    @Flag(default: false, description: "d") var d: Bool
    @Flag(default: false, description: "e") var e: Bool
}

private final class CountingSource: MutableFlagValueSource, @unchecked Sendable {
    let sourceName = "counting"
    var writes = 0

    private let lock = NSLock()
    private var values: [FlagKey: FlagValueBox] = [:]

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    var changes: AnyPublisher<FlagChange, Never> { Empty().eraseToAnyPublisher() }

    func setBox(_ box: FlagValueBox?, for key: FlagKey) throws {
        lock.lock()
        defer { lock.unlock() }
        writes += 1
        values[key] = box
    }
}

// MARK: - Import validates enum cases, as remote overrides do

extension AdversarialRegressionTests {

    /// A document naming a case this build does not have is refused.
    ///
    /// The remote path rejects exactly this, on the grounds that a value the app cannot
    /// represent would otherwise fall back to the default on every read — invisible in
    /// the editor, and indistinguishable from a flag that simply does not work. An
    /// imported document arrives from an older or newer build all the time, so the same
    /// reasoning applies with more force.
    func testImportingAnEnumCaseThisBuildLacksIsRejected() throws {
        let local = SnapshotSource()
        let pole = FlagPole(CaseCheckedFlags.self, sources: [local])

        let document = Data(#"{"formatVersion": 1, "values": {"tier": "platinum"}}"#.utf8)

        XCTAssertThrowsError(try pole.importPayload(document, as: .json)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownCase])
            XCTAssertEqual(problems.map(\.key), ["tier"])
        }

        XCTAssertNil(local.values["tier"], "nothing is stored")
        XCTAssertEqual(pole.tier, .free)
    }

    /// A case this build does have still imports.
    func testImportingAKnownEnumCaseStillWorks() throws {
        let pole = FlagPole(CaseCheckedFlags.self, sources: [SnapshotSource()])

        try pole.importPayload(
            Data(#"{"formatVersion": 1, "values": {"tier": "pro"}}"#.utf8), as: .json
        )
        XCTAssertEqual(pole.tier, .pro)
    }

    /// The same check on the scanned path, which shares the decoder.
    func testAScannedCodeWithAnUnknownCaseIsRejected() throws {
        let sender = FlagPole(WiderCaseFlags.self, sources: [SnapshotSource()])
        try sender.setOverride(WiderTier.platinum, for: sender.flags.$tier)
        let scanned = try sender.qrCodeString()

        let receiver = FlagPole(CaseCheckedFlags.self, sources: [SnapshotSource()])
        XCTAssertThrowsError(try receiver.importQRCode(scanned)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownCase])
        }
        XCTAssertEqual(receiver.tier, .free)
    }
}

private enum CaseCheckedTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}

/// A build with a case the receiving build has never heard of.
private enum WiderTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro, platinum
}

@FlagContainer
private struct CaseCheckedFlags {

    @Flag(default: CaseCheckedTier.free, description: "Tier")
    var tier: CaseCheckedTier
}

@FlagContainer
private struct WiderCaseFlags {

    @Flag(default: WiderTier.free, description: "Tier")
    var tier: WiderTier
}
