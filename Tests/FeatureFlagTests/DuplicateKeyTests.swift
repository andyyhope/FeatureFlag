import XCTest

@testable import FeatureFlag

/// Two flags can resolve to one storage key, and until this was fixed the result was a
/// crash inside `Dictionary(uniqueKeysWithValues:)` — with Swift's generic message, at
/// whatever moment the app first imported a document or applied a remote payload, which
/// could easily be on a tester's device rather than the developer's.
///
/// It needs no exotic setup: two property names that differ only in how an acronym is
/// cased collapse to the same kebabcase key. Any custom `KeyEncoding` that is not
/// injective does it far more easily.
final class DuplicateKeyTests: XCTestCase {

    /// Schemas built by hand stay permissive, so a collision can be inspected rather
    /// than only crashed into. The container-based initialiser is the strict one.
    private func collidingSchema() -> FlagSchema {
        FlagSchema(
            flags: [
                FlagSchema.Entry(
                    key: "use-https-only",
                    propertyPath: ["useHTTPSOnly"],
                    description: "A",
                    valueType: .bool,
                    defaultValue: .bool(false)
                ),
                FlagSchema.Entry(
                    key: "use-https-only",
                    propertyPath: ["useHttpsOnly"],
                    description: "B",
                    valueType: .bool,
                    defaultValue: .bool(false)
                ),
            ]
        )
    }

    // MARK: - Finding them

    func testACollisionIsReportedWithEveryPropertyThatCausedIt() {
        let duplicates = collidingSchema().duplicateKeys

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates["use-https-only"], [["useHTTPSOnly"], ["useHttpsOnly"]])
    }

    func testAHealthySchemaReportsNoDuplicates() {
        XCTAssertTrue(FlagSchema(DuplicateFreeFlags.self).duplicateKeys.isEmpty)
    }

    /// The names have to be good enough to act on, since the whole point is that the
    /// message is what someone gets instead of a debugger.
    func testTheReportNamesThePropertyPathsNotJustTheKey() throws {
        let message = try XCTUnwrap(collidingSchema().duplicateKeyDescription)

        XCTAssertTrue(message.contains("use-https-only"), message)
        XCTAssertTrue(message.contains("useHTTPSOnly"), message)
        XCTAssertTrue(message.contains("useHttpsOnly"), message)
    }

    func testAHealthySchemaHasNothingToDescribe() {
        XCTAssertNil(FlagSchema(DuplicateFreeFlags.self).duplicateKeyDescription)
    }

    // MARK: - Not trapping

    /// This is the crash itself. `valueTypes` is reached by every import, every scanned
    /// code and the companion's editor, so it must not trap on a schema it is handed.
    func testValueTypesDoesNotTrapOnACollision() {
        let types = collidingSchema().valueTypes
        XCTAssertEqual(types["use-https-only"], .bool)
    }

    func testValueCasesDoesNotTrapOnACollision() {
        XCTAssertTrue(collidingSchema().valueCases.isEmpty)
    }

    /// The other `Dictionary(uniqueKeysWithValues:)`, inside the remote source.
    func testApplyingARemotePayloadDoesNotTrapOnACollision() throws {
        let remote = RemoteOverrideSource(schema: collidingSchema())
        let result = try remote.apply(Data("{}".utf8), format: .json)
        XCTAssertTrue(result.appliedKeys.isEmpty)
    }

    // MARK: - Rejecting a published document

    /// A companion reads whatever the host published. A document naming one key twice is
    /// malformed, and saying so beats rendering an editor with two rows that fight.
    func testAPublishedSchemaWithADuplicateKeyIsRejected() {
        let data = Data(
            """
            {"formatVersion":1,"flags":[
              {"key":"a","valueType":"bool","defaultValue":false},
              {"key":"a","valueType":"bool","defaultValue":true}
            ]}
            """.utf8
        )

        XCTAssertThrowsError(try FlagSchema(jsonData: data)) { error in
            guard case let .malformed(message) = error as? FlagSchemaError else {
                return XCTFail("expected .malformed, got \(error)")
            }
            XCTAssertTrue(message.contains("a"), "the message should name the key: \(message)")
        }
    }

    func testAPublishedSchemaWithoutDuplicatesStillDecodes() throws {
        let schema = try FlagSchema(jsonData: FlagSchema(DuplicateFreeFlags.self).jsonData())
        XCTAssertEqual(schema.flags.count, 2)
    }
}

@FlagContainer
private struct DuplicateFreeFlags {

    @Flag(default: false, description: "One")
    var oneTap: Bool

    @Flag(default: false, description: "Two")
    var useHTTPSOnly: Bool
}
