/// The string a value source actually stores a flag under.
///
/// Keys are produced by applying a ``KeyEncoding`` to a ``FlagKeyPath``; they are not
/// written by hand except when reading an existing store.
public struct FlagKey: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

extension FlagKey: Codable {

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The position of a flag in its container tree, recorded as raw Swift property names.
///
/// The macro emits paths rather than finished keys because key encoding is configured
/// at runtime on the tower, and compile-time metadata cannot know it.
public struct FlagKeyPath: Hashable, Sendable {

    public let propertyNames: [String]

    public static let root = FlagKeyPath([])

    public init(_ propertyNames: [String]) {
        self.propertyNames = propertyNames
    }

    public func appending(_ propertyName: String) -> FlagKeyPath {
        FlagKeyPath(propertyNames + [propertyName])
    }
}
