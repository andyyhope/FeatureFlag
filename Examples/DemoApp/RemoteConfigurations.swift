import Foundation

/// A remote payload the demo can apply.
///
/// The framework never fetches, so these stand in for whatever your app would download.
/// Shipping them in the binary keeps the demo runnable on a simulator with no network
/// and no backend, while exercising exactly the same code path a real fetch would.
struct RemoteConfiguration: Identifiable, Hashable {

    let id: String
    let name: String
    let summary: String
    let json: String

    /// Whether this one is expected to be rejected, so the UI can say so up front
    /// rather than looking broken.
    let isDeliberatelyBroken: Bool

    var data: Data { Data(json.utf8) }
}

// MARK: - Driven by the environment

extension RemoteConfiguration {

    /// The payload an app would fetch for a given environment.
    ///
    /// In a real app this is the URL you would hit, not a constant — but the shape of
    /// the problem is identical, and everything interesting about it happens after the
    /// bytes arrive.
    static func forEnvironment(_ environment: DemoEnvironment) -> RemoteConfiguration {
        switch environment {
        case .production: return production
        case .staging: return staging
        case .local: return local
        }
    }

    static let production = RemoteConfiguration(
        id: "production",
        name: "Production",
        summary: "Conservative: new work off, live backend",
        json: """
            {
              "featureToggles": {
                "onboarding": { "v2": false },
                "checkout": { "applePay": false }
              },
              "config": {
                "apiEndpoint": "https://api.example.com",
                "paymentMethods": [
                  { "name": "Visa", "kind": "card", "enabled": true, "minimumSpend": 0 },
                  { "name": "Mastercard", "kind": "card", "enabled": true, "minimumSpend": 0 }
                ]
              }
            }
            """,
        isDeliberatelyBroken: false
    )

    static let staging = RemoteConfiguration(
        id: "staging",
        name: "Staging",
        summary: "Everything on, pointed at the staging backend",
        json: """
            {
              "featureToggles": {
                "onboarding": { "v2": true },
                "checkout": { "applePay": true }
              },
              "config": {
                "apiEndpoint": "https://staging.api.example.com",
                "paymentMethods": [
                  { "name": "Visa", "kind": "card", "enabled": true, "minimumSpend": 0 },
                  { "name": "Apple Pay", "kind": "wallet", "enabled": true, "minimumSpend": 0 },
                  { "name": "Bank transfer", "kind": "transfer", "enabled": true, "minimumSpend": 10 }
                ]
              }
            }
            """,
        isDeliberatelyBroken: false
    )

    static let local = RemoteConfiguration(
        id: "local",
        name: "Local",
        summary: "Everything on, pointed at a machine on your desk",
        json: """
            {
              "featureToggles": {
                "onboarding": { "v2": true },
                "checkout": { "applePay": true }
              },
              "config": {
                "apiEndpoint": "http://localhost:8080",
                "paymentMethods": [
                  { "name": "Test card", "kind": "card", "enabled": true, "minimumSpend": 0 }
                ]
              }
            }
            """,
        isDeliberatelyBroken: false
    )
}

// MARK: - Applied by hand

extension RemoteConfiguration {

    /// Offered as a button rather than reached through an environment, because the
    /// point of it is the failure.
    ///
    /// One bad field. Applying is all-or-nothing, so the valid `applePay` beside it is
    /// not applied either — the app never runs on half a configuration.
    static let malformed = RemoteConfiguration(
        id: "malformed",
        name: "Malformed payload",
        summary: #"onboarding.v2 sends "yes" where a boolean belongs"#,
        json: """
            {
              "featureToggles": {
                "onboarding": { "v2": "yes" },
                "checkout": { "applePay": true }
              },
              "config": { "apiEndpoint": "https://api.example.com" }
            }
            """,
        isDeliberatelyBroken: true
    )
}

// MARK: - A shape no path can address

extension RemoteConfiguration {

    /// The flags arrive as a list, and the flag's name is a field rather than a key.
    ///
    /// Nothing to do with ``FlagRecords``: this is a payload shape, not a flag type.
    /// The flags it sets are ordinary booleans.
    ///
    /// `DotPathMapper` finds nothing here — no path addresses "the record whose flag is
    /// new-onboarding" — so without `DemoRemoteMapper` this payload would apply cleanly
    /// and change absolutely nothing.
    static let experiments = RemoteConfiguration(
        id: "experiments",
        name: "List of experiments",
        summary: "A shape no dot path can reach, reshaped by a custom mapper",
        json: """
            {
              "experiments": [
                { "flag": "new-onboarding", "enabled": true },
                { "flag": "checkout.apple-pay", "enabled": true }
              ]
            }
            """,
        isDeliberatelyBroken: false
    )

    /// The same shape with one flag misspelled.
    ///
    /// `DotPathMapper` cannot produce an unknown key — it only ever emits keys it read
    /// from the schema — but a custom mapper with a typo can, which is the whole reason
    /// that problem kind exists. Applying is all-or-nothing, so the valid record beside
    /// it is not applied either.
    static let experimentsWithATypo = RemoteConfiguration(
        id: "experiments-typo",
        name: "List of experiments, misspelled",
        summary: "new-onbaording is not a flag this app has",
        json: """
            {
              "experiments": [
                { "flag": "new-onbaording", "enabled": true },
                { "flag": "checkout.apple-pay", "enabled": true }
              ]
            }
            """,
        isDeliberatelyBroken: true
    )
}
