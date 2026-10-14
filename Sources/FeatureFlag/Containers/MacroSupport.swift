/// The names macro-generated code reaches this module through. Not public API.
///
/// Generated code cannot spell a reference `FeatureFlag.FlagLookup`: a host module that
/// declares its own type called `FeatureFlag` — an enum of flag names is the obvious
/// thing to write — shadows the *module* name inside that module, and every such
/// reference is then looked up as a member of the host's type. Unqualified names are no
/// better, since a host is just as likely to declare its own `Flag` or `FlagKey`.
///
/// So the macros spell every reference through this one namespace instead, whose name
/// no host will plausibly declare. Module selectors (`FeatureFlag::FlagLookup`) would
/// solve this directly, but they are not available to every toolchain this package
/// supports.
///
/// Everything here exists only for the expansions of ``FlagContainer()`` and
/// ``FlagRecord()``. Use the module's own names in hand-written code; this may change
/// without notice.
public enum _FeatureFlagMacroSupport {

    public typealias Flag<Value: FlagValue> = FeatureFlag.Flag<Value>
    public typealias FlagContainer = FeatureFlag.FlagContainer
    public typealias FlagLookup = FeatureFlag.FlagLookup
    public typealias FlagKeyPath = FeatureFlag.FlagKeyPath
    public typealias FlagDescriptor = FeatureFlag.FlagDescriptor
    public typealias FlagGroupDescriptor = FeatureFlag.FlagGroupDescriptor
    public typealias FlagSchemaNode = FeatureFlag.FlagSchemaNode
    public typealias FlagRecord = FeatureFlag.FlagRecord
    public typealias FlagRecordField = FeatureFlag.FlagRecordField
    public typealias FlagValue = FeatureFlag.FlagValue
    public typealias FlagValueBox = FeatureFlag.FlagValueBox
    public typealias FlagValueType = FeatureFlag.FlagValueType

    /// Forwards to ``_flagValueCases(of:)``.
    public static func flagValueCases<Value: FeatureFlag.FlagValue>(
        of type: Value.Type
    ) -> [FeatureFlag.FlagValueBox]? {
        FeatureFlag._flagValueCases(of: type)
    }

    /// Forwards to ``_flagRecordShape(of:)``.
    public static func flagRecordShape<Value: FeatureFlag.FlagValue>(
        of type: Value.Type
    ) -> [FeatureFlag.FlagRecordField]? {
        FeatureFlag._flagRecordShape(of: type)
    }
}
