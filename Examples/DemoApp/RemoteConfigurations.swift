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
              "config": { "apiEndpoint": "https://api.example.com" }
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
              "config": { "apiEndpoint": "https://staging.api.example.com" }
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
              "config": { "apiEndpoint": "http://localhost:8080" }
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
