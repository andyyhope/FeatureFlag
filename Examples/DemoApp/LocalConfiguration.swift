import Foundation

/// A config that ships *inside* the app for an environment — the local layer beneath the
/// fetched remote one.
///
/// It stands in for a bundled `staging.json`: the values the build carries for an
/// environment before, or instead of, anything the backend sends. When the remote layer
/// is applied it wins; when the remote fetch fails or is cleared, these show through
/// rather than falling all the way to the compiled defaults — which is the point of
/// having a local layer at all.
struct LocalConfiguration {

    let json: String
    var data: Data { Data(json.utf8) }

    static func forEnvironment(_ environment: DemoEnvironment) -> LocalConfiguration {
        switch environment {
        case .production: return production
        case .staging: return staging
        case .local: return local
        }
    }

    /// Production's local layer points at the live endpoint and leaves Apple Pay off —
    /// a conservative baseline the remote config can turn on.
    static let production = LocalConfiguration(
        json: """
            {
              "featureToggles": { "checkout": { "applePay": false } },
              "config": { "apiEndpoint": "https://api.example.com" }
            }
            """
    )

    static let staging = LocalConfiguration(
        json: """
            {
              "featureToggles": { "checkout": { "applePay": false } },
              "config": { "apiEndpoint": "https://staging-local.example" }
            }
            """
    )

    static let local = LocalConfiguration(
        json: """
            {
              "featureToggles": { "checkout": { "applePay": true } },
              "config": { "apiEndpoint": "http://localhost:8080" }
            }
            """
    )
}
