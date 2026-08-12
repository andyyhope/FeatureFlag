import FeatureFlag
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var flags: FlagPole<AppFlags>

    var body: some View {
        NavigationStack {
            List {
                Section("Live flag values") {
                    LabeledContent("New onboarding", value: "\(flags.newOnboarding)")
                    LabeledContent("Page size", value: "\(flags.pageSize)")
                    LabeledContent("Markets", value: flags.markets.joined(separator: ", "))
                    LabeledContent("Apple Pay", value: "\(flags.checkout.applePay)")
                    LabeledContent("Tier", value: flags.checkout.tier.rawValue)
                    LabeledContent("One tap", value: "\(flags.checkout.express.oneTap)")
                }

                Section {
                    Text(
                        "Edit these in the companion app. Changes arrive while this app "
                            + "is running, via a Darwin notification, and again when it "
                            + "returns to the foreground."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Where each value came from") {
                    LabeledContent(
                        "New onboarding",
                        value: flags.resolution(for: flags.flags.$newOnboarding).sourceName
                            ?? "compiled default"
                    )
                    LabeledContent(
                        "Apple Pay",
                        value: flags.resolution(for: flags.flags.checkout.$applePay).sourceName
                            ?? "compiled default"
                    )
                }
            }
            .navigationTitle("Demo")
        }
    }
}
