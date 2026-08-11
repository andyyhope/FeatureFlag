import FeatureFlag
import FeatureFlagUI
import SwiftUI

/// The whole companion app.
///
/// It links no host code and knows nothing about `AppFlags` — it reads the schema the
/// host published into the shared App Group and renders whatever it finds. The same
/// build works for any app that publishes a schema to the same group.
@main
struct DemoCompanionApp: App {

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
        }
    }
}
