import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// The QR sheet could copy the image but not the code inside it, so a device that
/// cannot scan — a simulator, a Mac, a phone with no camera permission — had no way
/// to get overrides across.
final class FlagQRCodeTextTests: XCTestCase {

    private func makeStore(named name: String) -> FlagEditingStore {
        FlagEditingStore(schema: FlagSchema(QRFlags.self), source: SnapshotSource(name: name))
    }

    func testTheCopiedCodeIsSomethingTheImportFieldAccepts() throws {
        let sending = makeStore(named: "sending")
        let entry = try XCTUnwrap(sending.entry(for: "page-size"))
        try sending.setValue(.int(42), for: entry)

        let code = try sending.qrCodeString()

        let receiving = makeStore(named: "receiving")
        try receiving.importQRCode(code)

        XCTAssertEqual(receiving.value(for: entry), .int(42))
    }

    func testTheCodeIsPlainTextAPersonCanPaste() throws {
        let store = makeStore(named: "sending")
        let entry = try XCTUnwrap(store.entry(for: "page-size"))
        try store.setValue(.int(1), for: entry)

        let code = try store.qrCodeString()

        XCTAssertTrue(code.hasPrefix("FFQR1:"), code)
        XCTAssertFalse(code.contains(" "), "a code with spaces in it does not survive a paste")
    }

    func testCopyingIsOfferedOnlyWhenThereIsACodeToCopy() throws {
        // Nothing overridden is not a failure, but it is not a code worth copying
        // either — and offering one that encodes nothing invites a confusing import.
        let store = makeStore(named: "empty")

        XCTAssertNil(store.copyableQRCode)

        let entry = try XCTUnwrap(store.entry(for: "page-size"))
        try store.setValue(.int(7), for: entry)

        XCTAssertEqual(store.copyableQRCode, try store.qrCodeString())
    }

    func testAPayloadTooLargeToEncodeOffersNothingRatherThanThrowingIntoTheView() throws {
        let store = makeStore(named: "huge")
        let entry = try XCTUnwrap(store.entry(for: "note"))
        // Incompressible on purpose: the payload is deflated before it is encoded, so
        // twenty thousand identical characters fit in a code comfortably.
        try store.setValue(.string(incompressibleString(ofLength: 8_000)), for: entry)

        XCTAssertThrowsError(try store.qrCodeString())
        XCTAssertNil(store.copyableQRCode)
    }

    private func incompressibleString(ofLength count: Int) -> String {
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
private struct QRFlags {

    @Flag(default: 10, description: "Items per page")
    var pageSize: Int

    @Flag(default: "", description: "A note")
    var note: String
}
