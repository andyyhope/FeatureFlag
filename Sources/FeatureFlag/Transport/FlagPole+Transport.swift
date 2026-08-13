import Foundation

extension FlagPole {

    // MARK: - Schema

    /// Writes the schema where a companion app can find it.
    ///
    /// Call this on launch. The companion has no other way to learn what flags exist,
    /// what they are called, or what types they hold.
    @discardableResult
    public func publishSchema(inDirectory directory: URL) throws -> URL {
        try schema.write(toDirectory: directory)
    }

    /// Writes the schema into an App Group container shared with a companion app.
    ///
    /// Throws ``FlagSchemaError/notPublished`` when the group is missing from the
    /// target's entitlements.
    @discardableResult
    public func publishSchema(appGroup groupIdentifier: String) throws -> URL {
        guard let container = FlagSchema.containerURL(forAppGroup: groupIdentifier) else {
            throw FlagSchemaError.notPublished
        }
        return try publishSchema(inDirectory: container)
    }

    // MARK: - Export

    /// Every flag some source overrides, ready to serialise.
    public func exportPayload() -> FlagPayload {
        FlagPayload(values: overrides)
    }

    /// The current overrides as JSON or a property list.
    public func export(as format: FlagPayloadFormat) throws -> Data {
        try exportPayload().encoded(as: format)
    }

    // MARK: - Import

    /// Applies a payload's values as local overrides.
    ///
    /// Strict and all-or-nothing: if any key is unknown to this app, or holds a value
    /// of the wrong type, nothing is applied and every problem is reported at once.
    @discardableResult
    public func importPayload(_ data: Data, as format: FlagPayloadFormat) throws
        -> FlagImportResult
    {
        let payload = try FlagPayload.decode(
            data, as: format, valueTypes: schema.valueTypes, cases: schema.valueCases
        )
        return try apply(payload)
    }

    /// Applies an already-decoded payload as local overrides.
    ///
    /// If a write fails partway, the ones already made are undone. Decoding catches
    /// every problem it can see up front, but a source can still refuse a value, and
    /// "all-or-nothing" has to hold then too.
    ///
    /// The undo is best effort. A source that has stopped accepting writes altogether
    /// will refuse the undo as well, and nothing can be done about that.
    @discardableResult
    public func apply(_ payload: FlagPayload) throws -> FlagImportResult {
        let types = schema.valueTypes
        var undo: [(FlagKey, FlagValueBox?)] = []

        do {
            for (key, box) in payload.values {
                let previous = types[key].flatMap { currentOverride(for: key, as: $0) }
                try setOverride(box, for: key)
                undo.append((key, previous))
            }
        } catch {
            for (key, previous) in undo.reversed() {
                try? setOverride(previous, for: key)
            }
            throw error
        }

        return FlagImportResult(
            appliedKeys: payload.values.keys.sorted { $0.rawValue < $1.rawValue }
        )
    }
}
