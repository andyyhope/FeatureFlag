# FeatureFlag

[![CI](https://github.com/andyyhope/FeatureFlag/actions/workflows/ci.yml/badge.svg)](https://github.com/andyyhope/FeatureFlag/actions/workflows/ci.yml)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%20%7C%20macOS%2013%20%7C%20tvOS%2016%20%7C%20watchOS%209-lightgrey.svg)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Declare feature flags as Swift properties, read them type-safely, and edit them from a
separate companion app that never links a line of your code.

```swift
import FeatureFlag

@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding",
          remoteKey: "featureToggles.onboarding.v2")
    var newOnboarding: Bool

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

@FlagContainer
struct CheckoutFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool

    @Flag(default: Tier.free, description: "Pricing tier to present")
    var tier: Tier
}

enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}
```

```swift
let flags = FlagPole(
    AppFlags.self,
    sources: [
        UserDefaultsSource(appGroup: "group.example.flags")!,   // companion app edits
        RemoteOverrideSource(AppFlags.self),                    // your backend
    ]
)

if flags.checkout.applePay { … }
```

## Installation

Add the package in Xcode via **File → Add Package Dependencies**, or in `Package.swift`:

```swift
.package(url: "https://github.com/andyyhope/FeatureFlag.git", from: "0.1.0")
```

Then add `FeatureFlag` to your app target. Add `FeatureFlagUI` **only** to a companion
app — your shipping app never needs it, and never links it in the example.

## Requirements

Swift 5.9+, iOS 16 / macOS 13 / tvOS 16 / watchOS 9. Builds in Swift 5 language mode, so
adopting it does not drag you through a Swift 6 concurrency migration.

`FeatureFlagUI` is iOS and macOS only. watchOS has no `Menu`, `TextEditor` or bordered
text field, and a flag editor on a watch is not a real use case, so on other platforms it
compiles to nothing rather than pretending. The core module supports all four.

## What you get

- **Nested flags.** `@FlagGroup` namespaces keys — `checkout.express.one-tap`. Nesting is
  namespacing only: a child's value never depends on its parent, so there is no
  evaluation order to reason about.
- **Every type `UserDefaults` supports**, plus arrays, dictionaries, and
  `RawRepresentable` enums, which need no implementation beyond declaring conformance.
- **A companion app** sharing flags through an App Group, updating your app while it runs.
- **Remote overrides** from JSON or PLIST, mapped from whatever shape your backend sends.
- **Export and import** as JSON, PLIST, or a QR code.
- **Combine** publishers per flag, and `ObservableObject` for SwiftUI.

## The idea that makes it work

`@FlagContainer` generates `static var flagDescriptors` — a description of the flag tree
available **without an instance and without reflection**.

Everything else falls out of that. Your app writes those descriptors to a shared
container as a schema document; the companion reads it and renders an editor for an app
whose types it has never seen. One companion build works for any app that publishes a
schema. Remote key mapping, strict payload validation and editor selection all read the
same descriptors.

## Precedence

Sources are asked in order, so the order of the stack *is* the precedence:

```
1. local overrides    (companion app, imported JSON or QR)
2. remote payload     (your backend)
3. compiled default   (@Flag(default:))
```

A value you set by hand stays set until you clear it — which is what makes the companion
trustworthy for QA. `resolution(for:)` names the source that won:

```swift
flags.resolution(for: flags.flags.$newOnboarding).sourceName   // "App Group", or nil for the default
```

That is the answer to "why is this flag false?".

## Remote overrides

The framework decodes; it never fetches. Your app gets configuration however it likes and
hands over the bytes, so no networking, auth, retry or cache invalidation lives in a flag
library:

```swift
let (data, _) = try await URLSession.shared.data(from: url)
try remote.apply(data, format: .json)
```

Flags say where they live in the payload with `remoteKey`, read as a dot path
(`experiments.0.enabled` indexes into arrays). For a shape no path can address — a list of
records, say — implement `RemoteOverrideMapper`.

Applying is strict and all-or-nothing: one bad field rejects the payload and reports every
problem at once, rather than leaving your app running on half a configuration. Enum flags
are checked against their cases, so a backend sending a value you cannot represent fails
loudly instead of silently falling back on every read.

One deliberate allowance: JSON has a single number type, so a whole number satisfies a
`Double` flag. That is exact widening, not coercion — `"true"` is still not a boolean.

## The companion app

Your app publishes its schema on launch:

```swift
try flags.publishSchema(appGroup: "group.example.flags")
```

The companion renders it, linking none of your code:

```swift
import FeatureFlagUI

FlagBrowserView(store: try FlagEditingStore(appGroup: "group.example.flags"))
```

Edits reach your running app through a Darwin notification, because
`UserDefaults.didChangeNotification` does **not** fire for writes made by another process.
Sources also re-read on foreground, covering the case where your app was suspended and
missed one.

## Reading from other threads

`FlagPole` is not `@MainActor`. Reads are lock-protected and safe from any thread, because
apps read flags off the main thread constantly. Only `objectWillChange` is delivered on
the main thread, so SwiftUI observation stays correct.

## Two things worth knowing

**Export spans the whole stack.** `overrides`, and everything built on it, carries any
value that is not the compiled default — including one a remote payload supplied.
Exporting from a device with remote config and importing elsewhere turns those into local
overrides on the receiving device. Usually what you want from "reproduce this device's
state", but worth knowing before you share a code.

**`pole.someFlag` is a convenience, not the whole API.** Real members win over dynamic
member lookup, so a flag named `flags`, `keys`, `schema`, `overrides` or `descriptors` is
reached as `pole.flags.yourFlag`. Everything still works; only the shorthand is
unavailable for those five names.

**If your own module declares a type called `Flag`**, write `@FeatureFlag.Flag` instead. A
local `Flag` makes the bare attribute fail before any macro runs. Everything generated is
fully qualified, so nothing else can be shadowed.

## Example

[`Examples/FeatureFlagExamples.xcodeproj`](Examples/README.md) contains two iOS apps
sharing an App Group — a host that declares flags and a companion that edits them. Open it
and run `DemoApp`, then `DemoCompanion`.

| Host app | Companion app |
|---|---|
| ![DemoApp](Examples/Screenshots/host.png) | ![DemoCompanion](Examples/Screenshots/companion.png) |

## Credit where it is due

This framework is inspired by [**Vexil**](https://github.com/unsignedapps/Vexil) by
[Unsigned Apps](https://github.com/unsignedapps) — the best-established Swift feature flag
library, and worth using directly if it fits your needs. Several ideas here are Vexil's:
the `FlagPole` as the thing you read flags through, `@Flag` and `@FlagGroup` as property
wrappers, containers that namespace by nesting, and an ordered stack of `FlagValueSource`s
where position decides precedence.

No code was copied — this is an independent implementation, and both projects are MIT
licensed. Where the two differ, it is because this one was built to different
requirements:

| | Vexil | FeatureFlag |
|---|---|---|
| Companion UI | Vexillographer links your concrete flag types | Renders from a published schema, links none of your code |
| Streaming | `AsyncSequence` | Combine publishers |
| Language mode | Swift 6 tooling | Swift 5, no concurrency migration required |
| Remote config | — | `remoteKey` dot paths, custom mappers, strict validation |
| Transport | — | JSON, PLIST and QR export/import |

The decoupled companion is the reason this exists. Vexillographer is an excellent tool,
but it has to be built alongside the app it edits. Publishing a schema instead means one
companion build can edit any app that publishes one — at the cost of everything the editor
shows having to survive a trip through JSON.

## Status and contributing

Early. 360 tests, but the API may still move before 1.0. Issues and pull requests are
welcome — if you are reporting a bug, a failing test says more than a description.

## License

MIT. See [LICENSE](LICENSE).
