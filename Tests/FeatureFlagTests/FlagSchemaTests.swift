import XCTest

@testable import FeatureFlag

/// The schema is what decouples the companion app from the host: a separate binary
/// that has never seen `DemoFlags` can still render an editor for it.
final class FlagSchemaTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Building

    func testSchemaListsEveryFlagWithResolvedKeys() {
        let schema = FlagSchema(DemoFlags.self)
        XCTAssertEqual(
            schema.flags.map(\.key.rawValue),
            [
                "new-onboarding", "max-items", "checkout.apple-pay",
                "checkout.express.one-tap", "checkout.tier",
            ]
        )
    }

    func testSchemaUsesTheGivenKeyEncoding() {
        let schema = FlagSchema(DemoFlags.self, keyEncoding: .snakecase)
        XCTAssertTrue(schema.flags.contains { $0.key == "checkout.apple_pay" })
    }

    func testSchemaCarriesEditorMetadata() throws {
        let schema = FlagSchema(DemoFlags.self)
        let tier = try XCTUnwrap(schema.flags.first { $0.key == "checkout.tier" })

        XCTAssertEqual(tier.description, "Tier")
        XCTAssertEqual(tier.valueType, .string)
        XCTAssertEqual(tier.defaultValue, .string("free"))
        XCTAssertEqual(tier.cases, [.string("free"), .string("pro")])
        XCTAssertEqual(tier.propertyPath, ["checkout", "tier"])
    }

    func testSchemaCarriesRemoteKeysWhereDeclared() throws {
        let schema = FlagSchema(DemoFlags.self)
        let onboarding = try XCTUnwrap(schema.flags.first { $0.key == "new-onboarding" })
        let maxItems = try XCTUnwrap(schema.flags.first { $0.key == "max-items" })

        XCTAssertEqual(onboarding.remoteKey, "featureToggles.onboarding.v2")
        XCTAssertNil(maxItems.remoteKey)
    }

    func testSchemaDescribesGroupsSoTheEditorCanLabelSections() {
        let schema = FlagSchema(DemoFlags.self)
        XCTAssertEqual(
            schema.groups.map { ($0.propertyPath, $0.description) }.map { "\($0.0)=\($0.1)" },
            ["[\"checkout\"]=Checkout", "[\"checkout\", \"express\"]=Express"]
        )
    }

    // MARK: - Serialisation

    func testSchemaRoundTripsThroughJSON() throws {
        let schema = FlagSchema(DemoFlags.self, applicationName: "Demo")
        let decoded = try FlagSchema(jsonData: schema.jsonData())

        XCTAssertEqual(decoded.applicationName, "Demo")
        XCTAssertEqual(decoded.flags, schema.flags)
        XCTAssertEqual(decoded.groups, schema.groups)
    }

    func testSchemaJSONIsReadableByAnythingThatOpensIt() throws {
        let data = try FlagSchema(DemoFlags.self).jsonData()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        let flags = try XCTUnwrap(object["flags"] as? [[String: Any]])
        let first = try XCTUnwrap(flags.first)
        XCTAssertEqual(first["key"] as? String, "new-onboarding")
        XCTAssertEqual(first["valueType"] as? String, "bool")
        XCTAssertEqual(first["defaultValue"] as? Bool, false)
    }

    func testDecodingRejectsAnUnknownFormatVersion() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FlagSchema(DemoFlags.self).jsonData())
                as? [String: Any]
        )
        object["formatVersion"] = 99
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try FlagSchema(jsonData: data)) { error in
            XCTAssertEqual(error as? FlagSchemaError, .unsupportedFormatVersion(99))
        }
    }

    func testCollectionAndDateTypesSurviveTheRoundTrip() throws {
        let schema = FlagSchema(ExoticFlags.self)
        let decoded = try FlagSchema(jsonData: schema.jsonData())
        XCTAssertEqual(decoded.flags, schema.flags)

        let tags = try XCTUnwrap(decoded.flags.first { $0.key == "tags" })
        XCTAssertEqual(tags.valueType, .array(.string))
        XCTAssertEqual(tags.defaultValue, .array([.string("a")]))

        let launched = try XCTUnwrap(decoded.flags.first { $0.key == "launched-at" })
        XCTAssertEqual(launched.valueType, .date)
    }

    // MARK: - Publishing

    func testPublishingWritesASchemaTheCompanionCanRead() throws {
        let tower = FlagPole(DemoFlags.self, sources: [])
        let url = try tower.publishSchema(inDirectory: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = try FlagSchema(contentsOfDirectory: directory)
        XCTAssertEqual(loaded.flags.map(\.key), tower.schema.flags.map(\.key))
    }

    func testPublishingOverwritesAnEarlierSchema() throws {
        let tower = FlagPole(DemoFlags.self, sources: [])
        _ = try tower.publishSchema(inDirectory: directory)
        _ = try tower.publishSchema(inDirectory: directory)

        XCTAssertEqual(try FlagSchema(contentsOfDirectory: directory).flags.count, 5)
    }

    func testLoadingReportsAMissingSchemaClearly() {
        XCTAssertThrowsError(try FlagSchema(contentsOfDirectory: directory)) { error in
            XCTAssertEqual(error as? FlagSchemaError, .notPublished)
        }
    }
}

// MARK: - Fixtures

@FlagContainer
private struct ExoticFlags {

    @Flag(default: ["a"], description: "Tags")
    var tags: [String]

    @Flag(default: Date(timeIntervalSince1970: 0), description: "Launched at")
    var launchedAt: Date

    @Flag(default: [:], description: "Limits")
    var limits: [String: Int]
}
