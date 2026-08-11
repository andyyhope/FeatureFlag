import Compression
import Foundation

#if canImport(CoreImage)
    import CoreGraphics
    import CoreImage
#endif

public enum FlagQRCodeError: Error, Equatable {

    /// The payload will not fit in a single QR code, even compressed.
    ///
    /// Carries the override count so the message can say what to remove.
    case payloadTooLarge(bytes: Int, limit: Int, overrideCount: Int)

    /// Not a flag code, or a version this build does not understand.
    case unrecognisedFormat

    /// A flag code that could not be decompressed — usually a partial scan.
    case corrupt

    case imageGenerationFailed
}

/// Carries flag overrides in a QR code.
///
/// The wire format is `FFQR1:` followed by base64url of a deflate-compressed payload.
/// Compression is what makes this practical: flag keys and JSON structure repeat
/// heavily, so realistic payloads shrink by an order of magnitude and fit where the
/// raw JSON would not.
///
/// Only overrides travel, never the whole flag tree. No camera UI ships here —
/// ``decode(_:valueTypes:)`` takes whatever string your scanner produced.
public enum FlagQRCode {

    /// Identifies a flag code and its wire format version.
    public static let prefix = "FFQR1:"

    /// Capacity of the largest QR code (version 40) at error correction level L in
    /// byte mode. The encoded string must fit within this.
    public static let maximumEncodedLength = 2_953

    // MARK: - Encoding

    /// Compresses and encodes a payload.
    ///
    /// Throws ``FlagQRCodeError/payloadTooLarge(bytes:limit:overrideCount:)`` when the
    /// result will not fit in one code.
    public static func encode(_ payload: FlagPayload) throws -> String {
        let json = try payload.encoded(as: .json)
        let encoded = prefix + base64URLEncoded(compress(json))

        guard encoded.count <= maximumEncodedLength else {
            throw FlagQRCodeError.payloadTooLarge(
                bytes: encoded.count,
                limit: maximumEncodedLength,
                overrideCount: payload.values.count
            )
        }
        return encoded
    }

    // MARK: - Decoding

    /// Decodes a scanned string, validating every value against the app's own flags.
    ///
    /// A code produced by another app's build is rejected rather than partially
    /// applied — the same strictness as any other import.
    public static func decode(
        _ scanned: String,
        valueTypes: [FlagKey: FlagValueType]
    ) throws -> FlagPayload {
        guard scanned.hasPrefix(prefix) else { throw FlagQRCodeError.unrecognisedFormat }

        let body = String(scanned.dropFirst(prefix.count))
        guard let compressed = base64URLDecoded(body) else { throw FlagQRCodeError.corrupt }
        guard let json = decompress(compressed) else { throw FlagQRCodeError.corrupt }

        return try FlagPayload.decode(json, as: .json, valueTypes: valueTypes)
    }

    // MARK: - Image

    #if canImport(CoreImage)
        /// Renders a payload as a QR code image.
        ///
        /// Error correction stays at level L, the lowest, because capacity matters more
        /// than damage tolerance for a code shown on one screen and scanned by another.
        public static func image(for payload: FlagPayload, scale: CGFloat = 10) throws -> CGImage {
            let string = try encode(payload)

            guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
                throw FlagQRCodeError.imageGenerationFailed
            }
            filter.setValue(Data(string.utf8), forKey: "inputMessage")
            filter.setValue("L", forKey: "inputCorrectionLevel")

            guard let output = filter.outputImage else {
                throw FlagQRCodeError.imageGenerationFailed
            }
            let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else {
                throw FlagQRCodeError.imageGenerationFailed
            }
            return image
        }
    #endif
}

// MARK: - Compression

extension FlagQRCode {

    /// Deflates `data`, prefixed with its uncompressed length so decoding can size its
    /// buffer exactly.
    private static func compress(_ data: Data) -> Data {
        var result = Data()
        withUnsafeBytes(of: UInt32(data.count).bigEndian) { result.append(contentsOf: $0) }

        let capacity = max(data.count, 64)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let written = data.withUnsafeBytes { source in
            compression_encode_buffer(
                destination,
                capacity,
                source.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        // A zero return means it could not be made smaller. Store it as it is; the
        // length prefix still tells the decoder what to expect.
        if written == 0 {
            result.append(data)
        } else {
            result.append(destination, count: written)
        }
        return result
    }

    private static func decompress(_ data: Data) -> Data? {
        guard data.count >= 4 else { return nil }

        let expectedCount = data.prefix(4).reduce(into: UInt32(0)) { $0 = ($0 << 8) | UInt32($1) }
        let body = data.dropFirst(4)

        guard expectedCount > 0 else { return body.isEmpty ? Data() : nil }
        // Guard against a corrupt length claiming an implausible allocation.
        guard expectedCount <= 50_000_000 else { return nil }

        let capacity = Int(expectedCount)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let written = body.withUnsafeBytes { source in
            compression_decode_buffer(
                destination,
                capacity,
                source.bindMemory(to: UInt8.self).baseAddress!,
                body.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if written == capacity {
            return Data(bytes: destination, count: written)
        }
        // Not compressible when encoded, so it was stored verbatim.
        if body.count == capacity {
            return Data(body)
        }
        return nil
    }
}

// MARK: - base64url

extension FlagQRCode {

    /// base64url without padding: no characters a QR code or URL would need escaped.
    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ string: String) -> Data? {
        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - Tower conveniences

extension SignalTower {

    /// The current overrides, encoded for a QR code.
    public func qrCodeString() throws -> String {
        try FlagQRCode.encode(exportPayload())
    }

    #if canImport(CoreImage)
        /// The current overrides, rendered as a QR code.
        public func qrCodeImage(scale: CGFloat = 10) throws -> CGImage {
            try FlagQRCode.image(for: exportPayload(), scale: scale)
        }
    #endif

    /// Applies a scanned flag code.
    @discardableResult
    public func importQRCode(_ scanned: String) throws -> FlagImportResult {
        let payload = try FlagQRCode.decode(scanned, valueTypes: schema.valueTypes)
        return try apply(payload)
    }
}
