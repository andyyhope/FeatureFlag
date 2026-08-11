/// SemaphoreUI — schema-driven SwiftUI for editing feature flags.
///
/// This module is intended for a companion app. A host app should never link it:
/// the views render from a published ``FlagSchema`` and never see the host's
/// concrete flag types.
public enum SemaphoreUI {}
