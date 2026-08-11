import FeatureFlag

/// Shared flag tree for the tests in this target. Deliberately covers the awkward
/// cases: two levels of nesting, a remote key on some flags but not others, and a
/// CaseIterable enum.
@FlagContainer
struct DemoFlags {

    @Flag(default: false, description: "New onboarding", remoteKey: "featureToggles.onboarding.v2")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Maximum items")
    var maxItems: Int

    @FlagGroup(description: "Checkout")
    var checkout: DemoCheckoutFlags
}

@FlagContainer
struct DemoCheckoutFlags {

    @Flag(default: false, description: "Apple Pay", remoteKey: "featureToggles.checkout.applePay")
    var applePay: Bool

    @FlagGroup(description: "Express")
    var express: DemoExpressFlags

    @Flag(default: DemoTier.free, description: "Tier")
    var tier: DemoTier
}

@FlagContainer
struct DemoExpressFlags {

    @Flag(default: false, description: "One tap")
    var oneTap: Bool
}

enum DemoTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
}
