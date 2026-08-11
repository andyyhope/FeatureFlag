// FeatureFlagUI — schema-driven SwiftUI for editing feature flags.
//
// This module is for a companion app. A host app should never link it: the views
// render from a published FlagSchema and never see the host's concrete flag types.
//
// As in the FeatureFlag module, nothing here may be *named* FeatureFlagUI — a type
// sharing its module's name shadows that module for qualified lookups.
