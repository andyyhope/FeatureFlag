import Foundation

/// A remote payload the demo can apply on demand.
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

extension RemoteConfiguration {

    static let all: [RemoteConfiguration] = [staging, killswitch, malformed]

    /// Turns everything on and points the app at a different backend.
    static let staging = RemoteConfiguration(
        id: "staging",
        name: "Staging rollout",
        summary: "Onboarding and Apple Pay on, pointed at the staging backend",
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

    /// The production incident case: turn a feature off from the backend.
    ///
    /// Worth applying *after* setting an override in the companion — a local override
    /// sits above remote, so it survives, which is the whole point of the ordering.
    static let killswitch = RemoteConfiguration(
        id: "killswitch",
        name: "Killswitch",
        summary: "Everything off, as a backend would send during an incident",
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

    /// One bad field. Applying is all-or-nothing, so Apple Pay below it is *not*
    /// applied either — the app never runs on half a configuration.
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
