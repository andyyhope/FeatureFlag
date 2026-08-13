import XCTest

@testable import FeatureFlag

final class TransportEdgeCaseTests: XCTestCase {

    private func makePole() -> FlagPole<DemoFlags> {
        FlagPole(DemoFlags.self, sources: [SnapshotSource(name: "local")])
    }

    private var types: [FlagKey: FlagValueType] { makePole().schema.valueTypes }

    // MARK: - Malformed schemas

    func testASchemaMissingItsVersionIsRejected() {
        let data = Data(#"{"flags": []}"#.utf8)
        XCTAssertThrowsError(try FlagSchema(jsonData: data)) { error in
            guard case .malformed = error as? FlagSchemaError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testASchemaMissingItsFlagsIsRejected() {
        let data = Data(#"{"formatVersion": 1}"#.utf8)
        XCTAssertThrowsError(try FlagSchema(jsonData: data)) { error in
            guard case .malformed = error as? FlagSchemaError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testASchemaThatIsNotAnObjectIsRejected() {
        XCTAssertThrowsError(try FlagSchema(jsonData: Data("[]".utf8)))
        XCTAssertThrowsError(try FlagSchema(jsonData: Data("garbage".utf8)))
    }

    func testAnEntryWithAnUnknownTypeNameIsRejected() {
        let data = Data(
            #"{"formatVersion":1,"flags":[{"key":"a","valueType":"banana","defaultValue":1}]}"#
                .utf8
        )
        XCTAssertThrowsError(try FlagSchema(jsonData: data))
    }

    func testAnEntryWhoseDefaultDoesNotMatchItsTypeIsRejected() {
        let data = Data(
            #"{"formatVersion":1,"flags":[{"key":"a","valueType":"int","defaultValue":"lots"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try FlagSchema(jsonData: data)) { error in
            guard case let .malformed(message) = error as? FlagSchemaError else {
                return XCTFail("expected .malformed")
            }
            XCTAssertTrue(message.contains("a"), "message should name the flag: \(message)")
        }
    }

    func testASchemaWithNoGroupsDecodesFine() throws {
        let data = Data(
            #"{"formatVersion":1,"flags":[{"key":"a","valueType":"int","defaultValue":1}]}"#
                .utf8
        )
        let schema = try FlagSchema(jsonData: data)
        XCTAssertTrue(schema.groups.isEmpty)
        XCTAssertEqual(schema.flags.first?.propertyPath, ["a"])
    }

    func testAnEmptyContainerProducesAnEmptySchema() {
        let schema = FlagSchema(EmptyFlags.self)
        XCTAssertTrue(schema.flags.isEmpty)
        XCTAssertTrue(schema.groups.isEmpty)
        XCTAssertTrue(schema.valueTypes.isEmpty)
    }

    func testWritingToAMissingDirectoryReports() {
        let directory = URL(fileURLWithPath: "/nowhere/at/all/\(UUID().uuidString)")
        XCTAssertThrowsError(try FlagSchema(DemoFlags.self).write(toDirectory: directory))
    }

    func testAnUnknownAppGroupNeverYieldsAUsableSchema() {
        // Unsandboxed macOS does not check the group against entitlements and hands
        // back a constructed path regardless, so a non-nil container URL proves
        // nothing. What matters is that loading still fails cleanly.
        let group = "group.does.not.exist.\(UUID().uuidString)"
        XCTAssertThrowsError(try FlagSchema(appGroup: group)) { error in
            XCTAssertEqual(error as? FlagSchemaError, .notPublished)
        }
    }

    func testLoadingFromAnUnknownAppGroupReports() {
        XCTAssertThrowsError(try FlagSchema(appGroup: "group.does.not.exist.\(UUID())")) { error in
            XCTAssertEqual(error as? FlagSchemaError, .notPublished)
        }
    }

    // MARK: - Malformed payloads

    func testAPayloadMissingItsValuesIsRejected() {
        let data = Data(#"{"formatVersion": 1}"#.utf8)
        XCTAssertThrowsError(try FlagPayload.decode(data, as: .json, valueTypes: types)) { error in
            guard case .malformed = error as? FlagImportError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testAPayloadMissingItsVersionIsRejected() {
        let data = Data(#"{"values": {}}"#.utf8)
        XCTAssertThrowsError(try FlagPayload.decode(data, as: .json, valueTypes: types))
    }

    func testJSONParsedAsAPropertyListIsRejected() {
        let data = Data(#"{"formatVersion": 1, "values": {}}"#.utf8)
        XCTAssertThrowsError(try FlagPayload.decode(data, as: .plist, valueTypes: types)) { error in
            guard case .malformed = error as? FlagImportError else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testAPropertyListThatIsNotADictionaryIsRejected() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [1, 2, 3], format: .xml, options: 0
        )
        XCTAssertThrowsError(try FlagPayload.decode(data, as: .plist, valueTypes: types))
    }

    func testAnEmptyPayloadIsValidAndAppliesNothing() throws {
        let payload = try FlagPayload.decode(
            Data(#"{"formatVersion": 1, "values": {}}"#.utf8), as: .json, valueTypes: types
        )
        XCTAssertTrue(payload.values.isEmpty)

        let pole = makePole()
        let result = try pole.importPayload(
            Data(#"{"formatVersion": 1, "values": {}}"#.utf8), as: .json
        )
        XCTAssertTrue(result.appliedKeys.isEmpty)
    }

    func testImportingLeavesUnmentionedOverridesAlone() throws {
        // Import applies what it carries; it is not a wholesale replacement.
        let pole = makePole()
        try pole.setOverride(true, for: pole.flags.$newOnboarding)

        _ = try pole.importPayload(
            Data(#"{"formatVersion": 1, "values": {"max-items": 3}}"#.utf8), as: .json
        )

        XCTAssertTrue(pole.flags.newOnboarding)
        XCTAssertEqual(pole.flags.maxItems, 3)
    }

    func testExportingAndImportingAnEmptySetRoundTrips() throws {
        let pole = makePole()
        _ = try pole.importPayload(try pole.export(as: .json), as: .json)
        XCTAssertTrue(pole.overrides.isEmpty)
    }

    // MARK: - QR boundaries

    func testAPayloadJustUnderTheLimitEncodes() throws {
        let pole = FlagPole(BigStringFlags.self, sources: [SnapshotSource(name: "local")])
        // Incompressible, so the encoded length tracks the value length closely.
        try pole.setOverride(randomBase64(ofLength: 1_800), for: pole.flags.$blob)

        let encoded = try pole.qrCodeString()
        XCTAssertLessThanOrEqual(encoded.count, FlagQRCode.maximumEncodedLength)
    }

    func testAPayloadJustOverTheLimitIsRefused() throws {
        let pole = FlagPole(BigStringFlags.self, sources: [SnapshotSource(name: "local")])
        try pole.setOverride(randomBase64(ofLength: 3_000), for: pole.flags.$blob)

        XCTAssertThrowsError(try pole.qrCodeString()) { error in
            guard case .payloadTooLarge = error as? FlagQRCodeError else {
                return XCTFail("expected .payloadTooLarge, got \(error)")
            }
        }
    }

    func testAnEmptyScannedStringIsRejected() {
        XCTAssertThrowsError(try FlagQRCode.decode("", valueTypes: types)) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .unrecognisedFormat)
        }
    }

    func testAPrefixWithNoBodyIsRejected() {
        XCTAssertThrowsError(try FlagQRCode.decode("FFQR1:", valueTypes: types)) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .corrupt)
        }
    }

    func testACorruptLengthPrefixDoesNotAllocateWildly() {
        // Four 0xFF bytes claim a 4GB payload. It must be refused, not attempted.
        let hostile = FlagQRCode.prefix + Data([0xFF, 0xFF, 0xFF, 0xFF, 0x00]).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertThrowsError(try FlagQRCode.decode(hostile, valueTypes: types)) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .corrupt)
        }
    }

    func testAValidCodeWithForeignKeysIsRejectedNotIgnored() throws {
        let payload = FlagPayload(values: ["not-a-flag": .bool(true)])
        let encoded = try FlagQRCode.encode(payload)

        XCTAssertThrowsError(try FlagQRCode.decode(encoded, valueTypes: types)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownKey])
        }
    }

    private func randomBase64(ofLength count: Int) -> String {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var bytes = Data(count: count)
        for index in bytes.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return bytes.base64EncodedString()
    }
}

// MARK: - Fixtures

@FlagContainer
private struct EmptyFlags {}

@FlagContainer
private struct BigStringFlags {

    @Flag(default: "", description: "Blob")
    var blob: String
}

extension TransportEdgeCaseTests {

    /// The documents claim to be readable and hand-editable. JSONSerialization escapes
    /// forward slashes by default, which turns every URL into something nobody wants to
    /// read, let alone correct by hand.
    func testExportedJSONDoesNotEscapeSlashes() throws {
        let pole = FlagPole(SlashFlags.self, sources: [SnapshotSource(name: "local")])
        try pole.setOverride(URL(string: "https://staging.example.com/v3")!, for: pole.flags.$endpoint)

        let json = String(decoding: try pole.export(as: .json), as: UTF8.self)

        XCTAssertTrue(json.contains("https://staging.example.com/v3"), json)
        XCTAssertFalse(json.contains(#"\/"#), "slashes should not be escaped")
    }

    func testAPublishedSchemaDoesNotEscapeSlashesEither() throws {
        let json = String(decoding: try FlagSchema(SlashFlags.self).jsonData(), as: UTF8.self)
        XCTAssertFalse(json.contains(#"\/"#), "slashes should not be escaped")
    }

    func testEscapingChangeDoesNotBreakTheRoundTrip() throws {
        let source = FlagPole(SlashFlags.self, sources: [SnapshotSource(name: "local")])
        try source.setOverride(URL(string: "https://a.example/x/y?z=1/2")!, for: source.flags.$endpoint)

        let destination = FlagPole(SlashFlags.self, sources: [SnapshotSource(name: "local")])
        _ = try destination.importPayload(try source.export(as: .json), as: .json)

        XCTAssertEqual(destination.overrides, source.overrides)
    }
}

@FlagContainer
private struct SlashFlags {
    @Flag(default: URL(string: "https://example.com")!, description: "Endpoint")
    var endpoint: URL
}
