import XCTest

@testable import FeatureFlag

final class FlagQRCodeTests: XCTestCase {

    private func makeTower() -> SignalTower<DemoFlags> {
        SignalTower(DemoFlags.self, sources: [SnapshotSource(name: "local")])
    }

    // MARK: - Wire format

    func testEncodedStringCarriesAVersionedPrefix() throws {
        let tower = makeTower()
        try tower.setOverride(true, for: tower.flags.$newOnboarding)

        XCTAssertTrue(try tower.qrCodeString().hasPrefix("FFQR1:"))
    }

    func testEncodedStringIsSafeForAQRCode() throws {
        // base64url, so no characters that need escaping and no padding.
        let tower = makeTower()
        try tower.setOverride(true, for: tower.flags.$newOnboarding)

        let body = try tower.qrCodeString().dropFirst("FFQR1:".count)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(CharacterSet(charactersIn: String(body)).isSubset(of: allowed))
    }

    // MARK: - Round trips

    func testOverridesSurviveAScan() throws {
        let source = makeTower()
        try source.setOverride(true, for: source.flags.$newOnboarding)
        try source.setOverride(7, for: source.flags.$maxItems)
        try source.setOverride(DemoTier.pro, for: source.flags.checkout.$tier)

        let destination = makeTower()
        _ = try destination.importQRCode(try source.qrCodeString())

        XCTAssertEqual(destination.overrides, source.overrides)
    }

    func testAnEmptySetOfOverridesRoundTrips() throws {
        let destination = makeTower()
        _ = try destination.importQRCode(try makeTower().qrCodeString())
        XCTAssertTrue(destination.overrides.isEmpty)
    }

    func testCompressionMakesRealisticPayloadsFit() throws {
        // Flag keys and JSON structure repeat heavily, which is exactly what deflate is
        // good at. Without it a payload this size would not fit in one code.
        let tower = SignalTower(ManyFlags.self, sources: [SnapshotSource(name: "local")])
        let value = String(repeating: "a moderately long override value. ", count: 8)
        for accessor in tower.flags.allAccessors {
            try tower.setOverride(value, for: accessor)
        }

        let uncompressed = try tower.export(as: .json).count
        let encoded = try tower.qrCodeString()

        XCTAssertGreaterThan(uncompressed, 2_953)
        XCTAssertLessThanOrEqual(encoded.count, 2_953)
    }

    // MARK: - Size limit

    func testAnOversizedPayloadIsRefusedWithSomethingActionable() throws {
        let tower = SignalTower(BlobFlags.self, sources: [SnapshotSource(name: "local")])
        // Incompressible bytes, so no amount of deflate can make this fit. A simple
        // congruential generator keeps the test deterministic.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        var bytes = Data(count: 8_000)
        for index in bytes.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
        }
        try tower.setOverride(bytes, for: tower.flags.$blob)

        XCTAssertThrowsError(try tower.qrCodeString()) { error in
            guard case let .payloadTooLarge(bytes, limit, overrideCount) =
                error as? FlagQRCodeError
            else {
                return XCTFail("expected .payloadTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(bytes, limit)
            XCTAssertEqual(limit, 2_953)
            XCTAssertEqual(overrideCount, 1)
        }
    }

    // MARK: - Rejecting bad input

    func testDecodingRejectsAStringThatIsNotAFlagCode() {
        let tower = makeTower()
        XCTAssertThrowsError(try tower.importQRCode("https://example.com")) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .unrecognisedFormat)
        }
    }

    func testDecodingRejectsAFutureFormatVersion() {
        let tower = makeTower()
        XCTAssertThrowsError(try tower.importQRCode("FFQR9:abcdef")) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .unrecognisedFormat)
        }
    }

    func testDecodingRejectsCorruptedContent() {
        let tower = makeTower()
        XCTAssertThrowsError(try tower.importQRCode("FFQR1:!!!not-base64!!!")) { error in
            XCTAssertEqual(error as? FlagQRCodeError, .corrupt)
        }
    }

    func testDecodingRejectsTruncatedContent() throws {
        let tower = makeTower()
        try tower.setOverride(true, for: tower.flags.$newOnboarding)
        let truncated = String(try tower.qrCodeString().dropLast(8))

        XCTAssertThrowsError(try makeTower().importQRCode(truncated))
    }

    func testScannedCodeStillValidatesAgainstTheSchema() throws {
        // A code from another app's build must not smuggle in unknown keys.
        let foreign = SignalTower(BlobFlags.self, sources: [SnapshotSource(name: "local")])
        try foreign.setOverride(Data([0x01]), for: foreign.flags.$blob)

        XCTAssertThrowsError(try makeTower().importQRCode(try foreign.qrCodeString())) { error in
            guard case .rejected = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
        }
    }

    // MARK: - Image

    #if canImport(CoreImage)
        func testProducesAScannableImage() throws {
            let tower = makeTower()
            try tower.setOverride(true, for: tower.flags.$newOnboarding)

            let image = try tower.qrCodeImage()
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertEqual(image.width, image.height)
        }

        func testImageScaleIsHonoured() throws {
            let tower = makeTower()
            let small = try tower.qrCodeImage(scale: 1)
            let large = try tower.qrCodeImage(scale: 8)
            XCTAssertEqual(large.width, small.width * 8)
        }
    #endif
}

// MARK: - Fixtures

@FlagContainer
private struct BlobFlags {

    @Flag(default: Data(), description: "Blob")
    var blob: Data
}

@FlagContainer
private struct ManyFlags {

    @Flag(default: "", description: "Alpha") var alpha: String
    @Flag(default: "", description: "Bravo") var bravo: String
    @Flag(default: "", description: "Charlie") var charlie: String
    @Flag(default: "", description: "Delta") var delta: String
    @Flag(default: "", description: "Echo") var echo: String
    @Flag(default: "", description: "Foxtrot") var foxtrot: String
    @Flag(default: "", description: "Golf") var golf: String
    @Flag(default: "", description: "Hotel") var hotel: String
    @Flag(default: "", description: "India") var india: String
    @Flag(default: "", description: "Juliett") var juliett: String
    @Flag(default: "", description: "Kilo") var kilo: String
    @Flag(default: "", description: "Lima") var lima: String
    @Flag(default: "", description: "Mike") var mike: String
    @Flag(default: "", description: "November") var november: String
    @Flag(default: "", description: "Oscar") var oscar: String
    @Flag(default: "", description: "Papa") var papa: String

    var allAccessors: [FlagAccessor<String>] {
        [
            $alpha, $bravo, $charlie, $delta, $echo, $foxtrot, $golf, $hotel,
            $india, $juliett, $kilo, $lima, $mike, $november, $oscar, $papa,
        ]
    }
}
