// FeatureFlag — a Swift-native feature flag framework.
//
// Declare flags with `@Flag` and `@FlagGroup` inside a type annotated with
// `@FlagContainer`, then read them through a `SignalTower`.
//
// Generated code refers to this module's types by their fully qualified names
// (`FeatureFlag.FlagLookup` and friends) so that a host app's own types cannot shadow
// them. Nothing in this module may therefore be *named* `FeatureFlag`: a type sharing
// the module's name makes every qualified reference ambiguous.
