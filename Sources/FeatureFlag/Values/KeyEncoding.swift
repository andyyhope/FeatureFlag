/// Turns a ``FlagKeyPath`` into the ``FlagKey`` a value source stores.
///
/// Each path component is transformed individually, then joined with `separator`, so
/// nesting always survives the transform intact.
public struct KeyEncoding: Sendable {

    /// Placed between path components. Defaults to `.`.
    public let separator: String

    private let transform: @Sendable (String) -> String

    public init(separator: String = ".", transform: @escaping @Sendable (String) -> String) {
        self.separator = separator
        self.transform = transform
    }

    public func key(for path: FlagKeyPath) -> FlagKey {
        FlagKey(path.propertyNames.map(transform).joined(separator: separator))
    }

    /// `checkout.express.oneTap` becomes `checkout.express.one-tap`. The default.
    public static let kebabcase = KeyEncoding { name in
        splitWords(name).map { $0.lowercased() }.joined(separator: "-")
    }

    /// `checkout.express.oneTap` becomes `checkout.express.one_tap`.
    public static let snakecase = KeyEncoding { name in
        splitWords(name).map { $0.lowercased() }.joined(separator: "_")
    }

    /// Property names are used exactly as written.
    public static let verbatim = KeyEncoding { $0 }
}

extension KeyEncoding {

    /// Splits a camel-cased identifier into words.
    ///
    /// A word starts at an uppercase character that either follows a non-uppercase
    /// character (`applePay` → `apple`, `Pay`) or ends a run of them (`useHTTPSOnly` →
    /// `use`, `HTTPS`, `Only`). Digits stay attached to the word they trail, so
    /// `checkoutV2` yields `checkout`, `V2`.
    static func splitWords(_ name: String) -> [String] {
        let characters = Array(name)
        var words = [String]()
        var current = ""

        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let startsWord = !previous.isUppercase
                let endsAcronym = previous.isUppercase && (next?.isLowercase ?? false)

                if startsWord || endsAcronym {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }

        if current.isEmpty == false {
            words.append(current)
        }
        return words
    }
}
