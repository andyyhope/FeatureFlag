# FeatureFlag

A Swift-native feature flag framework: declare flags as Swift properties, read them
type-safely, and edit them from a separate companion app that never links a line of your
code.

```swift
@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding",
          remoteKey: "featureToggles.onboarding.v2")
    var newOnboarding: Bool

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

let flags = FlagPole(
    AppFlags.self,
    sources: [UserDefaultsSource(appGroup: "group.example.flags")!,
              RemoteOverrideSource(AppFlags.self)]
)

if flags.checkout.applePay { … }
```

Requires Swift 5.9+, iOS 16 / macOS 13 / tvOS 16 / watchOS 9. Builds in Swift 5 language
mode — adopting it does not drag you through a Swift 6 concurrency migration.

## What it does

- **Nested flags.** `@FlagGroup` namespaces keys — `checkout.express.one-tap`. Nesting
  is namespacing only: a child's value never depends on its parent, so there is no
  evaluation order to reason about.
- **Every UserDefaults type**, plus arrays, dictionaries, and `RawRepresentable` enums,
  which need no implementation beyond declaring conformance.
- **A companion app** that shares flags through an App Group, and updates the host app
  while it is running.
- **Remote overrides** from JSON or PLIST, mapped from your backend's shape.
- **Export and import** as JSON, PLIST, or a QR code.
- **Combine** publishers per flag, and `ObservableObject` for SwiftUI.

## The idea that makes it work

`@FlagContainer` generates `static var flagDescriptors` — a description of the flag tree
available **without an instance and without reflection**.

Everything else falls out of that. The host writes those descriptors to a shared
container as a schema document; the companion app reads it and renders an editor for an
app whose types it has never seen. The same companion build works for any app that
publishes a schema. Remote key mapping, strict payload validation and editor selection
all read the same descriptors.

## Precedence

Sources are asked in order, so the order of the stack *is* the precedence. The
recommended arrangement:

```
1. local overrides    (companion app, imported JSON or QR)
2. remote payload     (your backend)
3. compiled default   (@Flag(default:))
```

A value you set by hand stays set until you clear it. `resolution(for:)` names the
source that won, which is the answer to "why is this flag false?".

## Remote overrides

The framework decodes; it never fetches. Your app gets configuration however it likes and
hands over the bytes — no networking, auth, retry or cache invalidation in a flag
library.

```swift
let data = try await URLSession.shared.data(from: url).0
try remote.apply(data, format: .json)
```

Flags say where they live in the payload with `remoteKey`, read as a dot path
(`experiments.0.enabled` indexes arrays). Applying is strict and all-or-nothing: one bad
field rejects the payload and reports every problem, rather than leaving the app running
on half a configuration.

One deliberate allowance — JSON has a single number type, so a whole number satisfies a
`Double` flag. That is exact widening, not coercion. `"true"` is still not a boolean.

## Reading from other threads

`FlagPole` is not `@MainActor`. Reads are lock-protected and safe from any thread,
because apps read flags off the main thread constantly. Only `objectWillChange` is
delivered on the main thread, so SwiftUI observation stays correct.

## Two things worth knowing

**Export spans the whole stack.** `overrides` and everything built on it — JSON, PLIST,
QR — carry any value that is not the compiled default, including one a remote payload
supplied. Exporting from a device with remote config and importing elsewhere therefore
turns those into local overrides on the receiving device. That is usually what you want
from "reproduce this device's state", but it is worth knowing before you share a code.

**`pole.someFlag` is a convenience, not the whole API.** Real members win over dynamic
member lookup, so a flag named `flags`, `keys`, `schema`, `overrides` or `descriptors` is
reached as `pole.flags.yourFlag` rather than `pole.yourFlag`. Everything still works;
only the shorthand is unavailable for those five names.

## A note on `Flag`

If your own module declares a type called `Flag`, write `@FeatureFlag.Flag` instead. A
local `Flag` makes the bare attribute fail before any macro runs. Everything generated is
fully qualified, so nothing else can be shadowed.

## Getting started

See [`Examples/`](Examples/README.md) for a host app and companion app sharing one App
Group, including the Xcode setup.
