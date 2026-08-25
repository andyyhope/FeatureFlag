import Foundation

/// What happened to one record between a flag's compiled default and a config's value.
public struct FlagRecordDiff: Sendable, Equatable {

    public enum Change: Sendable, Equatable {
        /// In the config, not the default.
        case added
        /// In the default, not the config.
        case removed
        /// In both, with these fields differing. Never empty.
        case changed([FlagFieldDiff])
    }

    /// How the record is named: its key value when the record has a key, otherwise its
    /// position as `[0]`, `[1]`, …
    public let identifier: String

    public let change: Change
}

/// One field of one record that differs between the default and the config.
public struct FlagFieldDiff: Sendable, Equatable {

    public let field: String
    public let defaultValue: FlagValueBox
    public let incomingValue: FlagValueBox
}

extension FlagRecordDiff {

    /// Diffs two record lists, pairing by key when the shape has one and by position
    /// otherwise.
    static func diff(
        default defaults: [[String: FlagValueBox]],
        incoming: [[String: FlagValueBox]],
        shape: [FlagRecordField]
    ) -> [FlagRecordDiff] {
        if let key = shape.first(where: \.isKey)?.name {
            return diffByKey(default: defaults, incoming: incoming, shape: shape, key: key)
        }
        return diffByIndex(default: defaults, incoming: incoming, shape: shape)
    }

    private static func diffByKey(
        default defaults: [[String: FlagValueBox]],
        incoming: [[String: FlagValueBox]],
        shape: [FlagRecordField],
        key: String
    ) -> [FlagRecordDiff] {
        func identity(_ record: [String: FlagValueBox]) -> String {
            // The key value plain, not quoted: it names the record, it is not one of the
            // values being diffed.
            switch record[key] {
            case let .string(value): return value
            case let .some(box): return box.diffFieldDescription
            case .none: return "?"
            }
        }
        func id(_ record: [String: FlagValueBox]) -> String {
            record[key]?.storageIdentity ?? ""
        }
        let incomingByID = Dictionary(
            incoming.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first }
        )
        let defaultIDs = Set(defaults.map(id))

        var diffs = [FlagRecordDiff]()
        // Removed and changed, in the default's order.
        for record in defaults {
            if let match = incomingByID[id(record)] {
                let fields = fieldDiffs(default: record, incoming: match, shape: shape)
                if fields.isEmpty == false {
                    diffs.append(.init(identifier: identity(record), change: .changed(fields)))
                }
            } else {
                diffs.append(.init(identifier: identity(record), change: .removed))
            }
        }
        // Added, in the config's order.
        for record in incoming where defaultIDs.contains(id(record)) == false {
            diffs.append(.init(identifier: identity(record), change: .added))
        }
        return diffs
    }

    private static func diffByIndex(
        default defaults: [[String: FlagValueBox]],
        incoming: [[String: FlagValueBox]],
        shape: [FlagRecordField]
    ) -> [FlagRecordDiff] {
        var diffs = [FlagRecordDiff]()
        for index in 0..<max(defaults.count, incoming.count) {
            let id = "[\(index)]"
            switch (defaults.indices.contains(index), incoming.indices.contains(index)) {
            case (true, true):
                let fields = fieldDiffs(default: defaults[index], incoming: incoming[index], shape: shape)
                if fields.isEmpty == false {
                    diffs.append(.init(identifier: id, change: .changed(fields)))
                }
            case (true, false):
                diffs.append(.init(identifier: id, change: .removed))
            case (false, true):
                diffs.append(.init(identifier: id, change: .added))
            case (false, false):
                break
            }
        }
        return diffs
    }

    private static func fieldDiffs(
        default base: [String: FlagValueBox],
        incoming: [String: FlagValueBox],
        shape: [FlagRecordField]
    ) -> [FlagFieldDiff] {
        shape.compactMap { field in
            let a = base[field.name]
            let b = incoming[field.name]
            guard a != b, let a, let b else { return nil }
            return FlagFieldDiff(field: field.name, defaultValue: a, incomingValue: b)
        }
    }
}

extension FlagValueBox {

    /// A field value for a diff line — generous where ``shortMessageDescription`` is
    /// terse, because the point of a diff is to see the values, not a fragment.
    var diffFieldDescription: String {
        func quote(_ text: String) -> String {
            text.count > 80 ? "\"\(text.prefix(80))…\"" : "\"\(text)\""
        }
        switch self {
        case let .string(value): return quote(value)
        case let .url(value): return quote(value.absoluteString)
        case let .bool(value): return String(value)
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .float(value): return String(value)
        case let .date(value): return flagDateFormatter.string(from: value)
        case let .data(value): return "\(value.count) bytes"
        case .array, .dictionary: return shortMessageDescription
        }
    }
}
