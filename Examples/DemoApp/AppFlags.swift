import FeatureFlag
import Foundation

/// The App Group both the host app and the companion app must declare in their
/// entitlements. Change this to one your team owns.
public let demoAppGroup = "group.com.andyyhope.featureflag.demo"

/// Which backend this build talks to.
///
/// Ordinary enum, ordinary flag. What makes it behave like an "environment" is not a
/// special type — it is that it has no `remoteKey`, so nothing the backend sends can
/// change it. See `DemoModel.switchTo(_:)` for why that matters.
public enum DemoEnvironment: String, FlagValue, CaseIterable, FlagValueCases {
    case production
    case staging
    case local
}

public enum CheckoutTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free
    case pro
    case enterprise
}

@FlagContainer
public struct AppFlags {

    /// Deliberately no `remoteKey`: this flag decides which payload gets fetched, so a
    /// payload must not be able to decide it back.
    @Flag(default: DemoEnvironment.production, description: "Which backend this build talks to")
    public var environment: DemoEnvironment

    @Flag(
        default: false,
        description: "Show the redesigned onboarding flow",
        remoteKey: "featureToggles.onboarding.v2"
    )
    public var newOnboarding: Bool

    @Flag(default: 10, description: "How many items to show per page")
    public var pageSize: Int

    @Flag(default: ["AU", "NZ"], description: "Markets the app is live in")
    public var markets: [String]

    @FlagGroup(description: "Checkout")
    public var checkout: CheckoutFlags
}

@FlagContainer
public struct CheckoutFlags {

    @Flag(
        default: false,
        description: "Offer Apple Pay at checkout",
        remoteKey: "featureToggles.checkout.applePay"
    )
    public var applePay: Bool

    @Flag(default: CheckoutTier.free, description: "Which pricing tier to present")
    public var tier: CheckoutTier

    @Flag(
        default: URL(string: "https://api.example.com")!,
        description: "Backend the app talks to",
        remoteKey: "config.apiEndpoint"
    )
    public var endpoint: URL

    @FlagGroup(description: "Express checkout")
    public var express: ExpressFlags
}

@FlagContainer
public struct ExpressFlags {

    @Flag(default: false, description: "Skip the review step")
    public var oneTap: Bool

    @Flag(default: 3.0, description: "Seconds before the order is placed")
    public var confirmationDelay: Double
}
