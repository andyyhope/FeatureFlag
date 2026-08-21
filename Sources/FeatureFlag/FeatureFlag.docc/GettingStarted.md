# Getting started

Go from an empty project to a flag you can toggle from a second app.

## Overview

This walks the whole path in five steps. Each one works on its own — you can stop after
step three and still have type-safe flags with defaults, and come back for the companion
app when you need someone else to change a value on a device you are not holding.

### 1. Add the package

In Xcode, **File → Add Package Dependencies**, or in `Package.swift`:

```swift
.package(url: "https://github.com/andyyhope/FeatureFlag.git", .upToNextMinor(from: "0.7.0"))
```

Add `FeatureFlag` to your app target. Add `FeatureFlagUI` **only** to a companion app —
your shipping app never links it.

Pre-1.0, `from:` would accept every breaking `0.x` bump. While the API is still moving,
`.upToNextMinor` is the constraint that matches what the package promises.

### 2. Declare your flags

A container is a plain type annotated with `@FlagContainer`. Every flag needs an explicit
type annotation, because a macro cannot infer types.

```swift
import FeatureFlag

@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool

    @Flag(default: 20, description: "Items per page")
    var pageSize: Int

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

@FlagContainer
struct CheckoutFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool
}
```

`description` is not a comment. It is what a companion app puts next to the control, so
write it for whoever is looking at the list wondering which switch to flip.

### 3. Build a pole and read flags

A ``FlagPole`` binds a container to an ordered stack of sources.

```swift
let flags = FlagPole(AppFlags.self, sources: [UserDefaultsSource()])

if flags.newOnboarding {
    showNewOnboarding()
}

if flags.checkout.applePay {
    addApplePayButton()
}
```

Make it one instance your app shares. Reads are lock-protected and safe from any thread,
so it does not need to live on the main actor — see
[Observing changes](doc:ObservingChanges).

With no override stored anywhere, every flag reports its compiled default. That is
already useful: you have one place that lists what your app can turn on, with
descriptions, and nothing to configure.

### 4. Share a suite with a companion app

Two apps can only see the same flags if they share an App Group.

1. Add the **App Groups** capability to both targets, with the same identifier —
   `group.com.example.flags` in these examples.
2. Point the source at the group, and publish the schema on launch:

```swift
let flags = FlagPole(
    AppFlags.self,
    sources: [UserDefaultsSource(appGroup: "group.com.example.flags")!]
)

try flags.publishSchema(appGroup: "group.com.example.flags")
```

Publishing writes `flag-schema.json` into the shared container. The companion has no
other way to learn what flags exist, what they are called, or what types they hold — it
never links your code.

``UserDefaultsSource/init(appGroup:name:)`` returns `nil` when the suite cannot be
opened. Force-unwrapping it is reasonable in an app you control, but do not read it as a
check that the entitlement is right — a group the target may not use does not reliably
come back `nil`, and the symptom you get instead is a companion whose edits never arrive.

`publishSchema(appGroup:)` on the next line is the better canary. It goes through the
container URL, which *is* checked against the entitlements on iOS, and throws
``FlagSchemaError/notPublished`` when the group is not one this target may use. Let that
throw be loud in a debug build.

### 5. Render it in the companion

The companion app is small. It reads the schema and edits the same shared suite:

```swift
import FeatureFlagUI
import SwiftUI

struct CompanionRootView: View {

    private let store = try? FlagEditingStore(appGroup: "group.com.example.flags")

    var body: some View {
        if let store {
            FlagOverridesView(store: store)
        } else {
            Text("Run the host app once so it can publish its schema.")
        }
    }
}
```

Edits reach your running app through a Darwin notification, because
`UserDefaults.didChangeNotification` does **not** fire for writes made by another
process. Sources also re-read on foreground, which covers the case where your app was
suspended and missed one.

`Examples/FeatureFlagExamples.xcodeproj` in the repository is exactly this: two iOS apps
sharing a group, one declaring flags and one editing them.

## Where to go next

- [Declaring flags](doc:DeclaringFlags) — nesting, keys, remote paths, and flags with no
  pole behind them.
- [Flag values](doc:FlagValues) — the types a flag can hold, including your own enums.
- [Sources and precedence](doc:SourcesAndPrecedence) — stacking sources, and finding out
  which one won.
- [Sharing flags with a companion app](doc:SharingWithACompanionApp) — what the schema
  carries and what it costs.
