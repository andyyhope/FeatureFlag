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
