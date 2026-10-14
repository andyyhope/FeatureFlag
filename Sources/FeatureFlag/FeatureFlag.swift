// FeatureFlag — a Swift-native feature flag framework.
//
// Declare flags with `@Flag` and `@FlagGroup` inside a type annotated with
// `@FlagContainer`, then read them through a `FlagPole`.
//
// Generated code refers to this module's types through `_FeatureFlagMacroSupport`
// (`_FeatureFlagMacroSupport.FlagLookup` and friends) so that a host app's own types
// cannot shadow them — including a host type named `FeatureFlag`, which would shadow
// the module name itself. Nothing in this module may be *named* `FeatureFlag`
// either: the support namespace's own aliases are spelled through the module name.
