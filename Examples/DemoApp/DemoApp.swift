import FeatureFlag
import SwiftUI

/// The host app. It links `FeatureFlag` only — never `FeatureFlagUI`, so no editor
/// code ships in the app people install.
@main
struct DemoApp: App {

    @StateObject private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    // The companion app is a separate binary and has no idea this flag
                    // tree exists until it is published. Do this on every launch so a
                    // newly added flag shows up straight away.
                    _ = try? model.flags.publishSchema(appGroup: demoAppGroup)
                }
        }
    }
}
