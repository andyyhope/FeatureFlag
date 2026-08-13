#if os(iOS) || os(macOS)

    import Foundation

    #if canImport(CoreGraphics)
        import CoreGraphics
    #endif

    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    #if canImport(CoreGraphics)

        /// Turning a generated code into something that can leave the app.
        ///
        /// A QR code is only useful once it is somewhere else — a chat message, a ticket,
        /// a file someone else can scan — so the sheet needs to hand it over as both an
        /// image and a file.
        enum FlagImageExport {

            /// PNG rather than JPEG: a QR code is hard edges and flat colour, which JPEG
            /// smears into exactly the artefacts a scanner struggles with.
            static func pngData(for image: CGImage) -> Data? {
                #if canImport(UIKit)
                    return UIImage(cgImage: image).pngData()
                #elseif canImport(AppKit)
                    let representation = NSBitmapImageRep(cgImage: image)
                    return representation.representation(using: .png, properties: [:])
                #else
                    return nil
                #endif
            }

            /// Writes the code to a temporary file so it can be shared as a document.
            ///
            /// Sharing a file rather than a bare image is what puts "Save to Files" in
            /// the share sheet, and it needs no photo library permission from whichever
            /// app is hosting this view.
            static func temporaryPNG(for image: CGImage, named name: String) -> URL? {
                guard let data = pngData(for: image) else { return nil }

                let url = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(name)
                    .appendingPathExtension("png")

                do {
                    try data.write(to: url, options: .atomic)
                    return url
                } catch {
                    return nil
                }
            }
        }

    #endif

#endif
