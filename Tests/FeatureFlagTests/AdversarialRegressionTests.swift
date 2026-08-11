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
