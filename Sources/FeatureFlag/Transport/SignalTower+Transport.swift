import Foundation

extension SignalTower {

    // MARK: - Schema

    /// This tower's flag tree, described so a companion app can render it without ever
    /// seeing `Root`.
    public var schema: FlagSchema {
        FlagSchema(
            Root.self,
            keyEncoding: keyEncoding,
            applicationName: Bundle.main.bundleIdentifier
        )
    }

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
        let payload = try FlagPayload.decode(data, as: format, valueTypes: schema.valueTypes)
        return try apply(payload)
    }

    /// Applies an already-decoded payload as local overrides.
    @discardableResult
    public func apply(_ payload: FlagPayload) throws -> FlagImportResult {
        for (key, box) in payload.values {
            try setOverride(box, for: key)
        }
        return FlagImportResult(
            appliedKeys: payload.values.keys.sorted { $0.rawValue < $1.rawValue }
        )
    }
}
