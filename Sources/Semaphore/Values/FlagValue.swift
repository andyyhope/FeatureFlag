import Foundation

/// A type that can be stored in and read back from a feature flag.
///
/// Conformance is supplied for every type `UserDefaults` supports. Enums get it for
/// free when their `RawValue` is itself a `FlagValue`.
///
/// Unboxing is deliberately strict: a box holding the wrong case yields `nil` rather
/// than coercing. Format-level ambiguity (JSON numbers, for instance) is resolved
/// where the target type is known, not here.
public protocol FlagValue: Sendable, Equatable {

    /// The type this value reports to schemas and to remote payload validation.
    static var flagValueType: FlagValueType { get }

    /// Recreates a value from its boxed form, or fails if the box holds another type.
    init?(box: FlagValueBox)

    /// The canonical boxed form of this value.
    var box: FlagValueBox { get }
}

// MARK: - Primitives

extension Bool: FlagValue {
    public static var flagValueType: FlagValueType { .bool }

    public init?(box: FlagValueBox) {
        guard case let .bool(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .bool(self) }
}

extension Int: FlagValue {
    public static var flagValueType: FlagValueType { .int }

    public init?(box: FlagValueBox) {
        guard case let .int(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .int(self) }
}

extension Double: FlagValue {
    public static var flagValueType: FlagValueType { .double }

    public init?(box: FlagValueBox) {
        guard case let .double(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .double(self) }
}

extension Float: FlagValue {
    public static var flagValueType: FlagValueType { .float }

    public init?(box: FlagValueBox) {
        guard case let .float(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .float(self) }
}

extension String: FlagValue {
    public static var flagValueType: FlagValueType { .string }

    public init?(box: FlagValueBox) {
        guard case let .string(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .string(self) }
}

extension Data: FlagValue {
    public static var flagValueType: FlagValueType { .data }

    public init?(box: FlagValueBox) {
        guard case let .data(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .data(self) }
}

extension Date: FlagValue {
    public static var flagValueType: FlagValueType { .date }

    public init?(box: FlagValueBox) {
        guard case let .date(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .date(self) }
}

extension URL: FlagValue {
    public static var flagValueType: FlagValueType { .url }

    public init?(box: FlagValueBox) {
        guard case let .url(value) = box else { return nil }
        self = value
    }

    public var box: FlagValueBox { .url(self) }
}

// MARK: - Collections

extension Array: FlagValue where Element: FlagValue {
    public static var flagValueType: FlagValueType { .array(Element.flagValueType) }

    public init?(box: FlagValueBox) {
        guard case let .array(boxes) = box else { return nil }
        var values = [Element]()
        values.reserveCapacity(boxes.count)
        for elementBox in boxes {
            guard let value = Element(box: elementBox) else { return nil }
            values.append(value)
        }
        self = values
    }

    public var box: FlagValueBox { .array(map(\.box)) }
}

extension Dictionary: FlagValue where Key == String, Value: FlagValue {
    public static var flagValueType: FlagValueType { .dictionary(Value.flagValueType) }

    public init?(box: FlagValueBox) {
        guard case let .dictionary(boxes) = box else { return nil }
        var values = [String: Value](minimumCapacity: boxes.count)
        for (key, valueBox) in boxes {
            guard let value = Value(box: valueBox) else { return nil }
            values[key] = value
        }
        self = values
    }

    public var box: FlagValueBox { .dictionary(mapValues(\.box)) }
}

// MARK: - Enums

/// Enums whose `RawValue` is itself a ``FlagValue`` need no implementation:
/// declaring conformance is enough.
///
/// ```swift
/// enum Tier: String, FlagValue { case free, pro }
/// ```
extension FlagValue where Self: RawRepresentable, Self.RawValue: FlagValue {
    public static var flagValueType: FlagValueType { RawValue.flagValueType }

    public init?(box: FlagValueBox) {
        guard let rawValue = RawValue(box: box) else { return nil }
        self.init(rawValue: rawValue)
    }

    public var box: FlagValueBox { rawValue.box }
}

/// Exposes a value type's full set of cases to editors.
///
/// The schema layer only ever holds a metatype, so this deliberately avoids
/// generics — it can be reached through an existential where `CaseIterable` cannot.
/// Conform a `CaseIterable` flag value to get a picker in the companion app instead
/// of a free-text field.
public protocol FlagValueCases {
    static var flagValueCases: [FlagValueBox] { get }
}

extension FlagValueCases where Self: CaseIterable, Self: FlagValue {
    public static var flagValueCases: [FlagValueBox] { allCases.map(\.box) }
}
