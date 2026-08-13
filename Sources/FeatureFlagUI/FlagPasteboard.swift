#if os(iOS) || os(macOS)

    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    /// Writing to the pasteboard, without each call site needing to know which platform
    /// it is on.
    enum FlagPasteboard {

        static func copy(_ string: String) {
            #if canImport(UIKit)
                UIPasteboard.general.string = string
            #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            #endif
        }

        #if canImport(CoreGraphics)
            /// Puts an image on the pasteboard, so a QR code can be pasted straight into
            /// a chat or a ticket rather than screenshotted.
            static func copy(image: CGImage) {
                #if canImport(UIKit)
                    UIPasteboard.general.image = UIImage(cgImage: image)
                #elseif canImport(AppKit)
                    let size = NSSize(width: image.width, height: image.height)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
                #endif
            }

            /// Whether the pasteboard is holding an image, for tests.
            static var hasImage: Bool {
                #if canImport(UIKit)
                    return UIPasteboard.general.image != nil
                #elseif canImport(AppKit)
                    return NSPasteboard.general.canReadObject(forClasses: [NSImage.self])
                #else
                    return false
                #endif
            }
        #endif

        /// What the pasteboard currently holds, for tests and for verifying a copy.
        static var current: String? {
            #if canImport(UIKit)
                return UIPasteboard.general.string
            #elseif canImport(AppKit)
                return NSPasteboard.general.string(forType: .string)
            #endif
        }
    }

#endif
