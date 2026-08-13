import FeatureFlag
import XCTest

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

@testable import FeatureFlagUI

/// The QR sheet's Copy and Save, which are the only ways a code leaves the screen
/// without someone photographing it with a second phone.
final class QRCodeExportTests: XCTestCase {

    private func makeStore() throws -> FlagEditingStore {
        let source = SnapshotSource(name: "shared")
        let store = FlagEditingStore(schema: FlagSchema(QRExportFlags.self), source: source)
        let entry = try XCTUnwrap(store.entry(for: "new-onboarding"))
        try store.setValue(.bool(true), for: entry)
        return store
    }

    func testTheCodeEncodesAsAPNG() throws {
        let image = try makeStore().qrCodeImage(scale: 4)
        let data = try XCTUnwrap(FlagImageExport.pngData(for: image))

        // PNG's magic number. JPEG would smear a QR code's hard edges into exactly the
        // artefacts a scanner struggles with, so the format matters.
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(data.count, 100)
    }

    func testSavingWritesAFileThatExists() throws {
        let image = try makeStore().qrCodeImage(scale: 4)
        let url = try XCTUnwrap(
            FlagImageExport.temporaryPNG(for: image, named: "qr-export-\(UUID().uuidString)")
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let written = try Data(contentsOf: url)
        XCTAssertEqual(Array(written.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testCopyingPutsAnImageOnThePasteboard() throws {
        let image = try makeStore().qrCodeImage(scale: 4)

        FlagPasteboard.copy(image: image)

        XCTAssertTrue(FlagPasteboard.hasImage)
    }

    /// The sheet itself still builds with the actions attached.
    func testTheSheetBuilds() throws {
        XCTAssertNotNil(FlagQRCodeView(store: try makeStore()).body)
    }
}

@FlagContainer
private struct QRExportFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}
