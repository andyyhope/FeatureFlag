# Examples

Two iOS apps sharing one App Group: a host app that declares flags, and a companion app
that edits them **without linking a line of the host's code**.

```
open Examples/FeatureFlagExamples.xcodeproj
```

Run **DemoApp** first, then **DemoCompanion**. Both are configured for ad-hoc signing, so
they run on a simulator with no team set up.

| Host app | Companion app |
|---|---|
| ![DemoApp](Screenshots/host.png) | ![DemoCompanion](Screenshots/companion.png) |

The host shows live values and, underneath, which source supplied each one. The companion
renders the same flags from the published schema — a toggle for the `Bool`, a number field
for the `Int`, a picker for the enum, a URL field — and marks what has been overridden.

Note what the host is showing: `Apple Pay` came from **Companion**, while `New onboarding`
is still the **compiled default**. That line is `resolution(for:)`, and it is the answer to
"why is this flag false?".

## How the companion knows anything

It has never seen `AppFlags`. On launch the host writes a schema describing its flag tree
into the shared container:

```swift
_ = try? flags.publishSchema(appGroup: demoAppGroup)
```

which produces `flag-schema.json`:

```json
{ "applicationName" : "Demo",
  "flags" : [ { "key" : "checkout.tier",
                "valueType" : "string",
                "defaultValue" : "free",
                "cases" : ["free", "pro", "enterprise"],
                "description" : "Which pricing tier to present" } ] }
```

The companion reads that file and builds its editor from it. `cases` is why the tier flag
gets a picker instead of a text field. One companion build works for **any** app that
publishes a schema to the same group.

## The environment flag drives the remote config

`DemoApp` has an `environment` flag — an ordinary `RawRepresentable` enum, not a special
type. Changing it applies that environment's payload:

```swift
flags.flags.$environment.publisher
    .removeDuplicates()
    .sink { [weak self] environment in self?.switchTo(environment) }
```

Two details carry the whole pattern.

**The environment flag has no `remoteKey`.** If it did, a staging payload could set the
environment to production — which would mean a different payload should have been fetched,
and applying *that* could set it back. Nothing in the framework stops you wiring that loop;
leaving the key off is what prevents it. A test asserts the key stays absent, and another
fires a payload that tries to set `environment` and checks it is ignored.

**The old environment's values are cleared before the new ones are applied.** That leaves a
brief window on compiled defaults, which is deliberate: an app labelled *staging* still
running yesterday's production values looks fine and is wrong, which is worse than one
running its own defaults.

Overrides still outrank everything. Set Apple Pay in the companion, then switch
environment — the override survives, and "Where each value came from" says `Companion`.
Clear it and the environment's value shows through.

## Rejecting a bad payload

One button applies a deliberately malformed payload: `onboarding.v2` sends `"yes"` where a
boolean belongs. It is rejected in full, and the valid `applePay` beside it is not applied
either.

`Tests/DemoExamplesTests` checks every payload against the real flag tree, because a
mistyped dot path fails silently as "the backend sent nothing" — the exact bug the demo
exists to make visible. The tests assert `absentKeys` is empty so a wrong path fails
loudly.

## Signals: asking the host to do something

Flags let the companion change what the host *reads*. Signals let it ask the host to *act*:

```swift
// shared by both targets
public enum AppSignal: String, FlagSignal {
    case refetchRemoteConfiguration
    case clearRemoteConfiguration
}

// companion
try await channel.send(AppSignal.refetchRemoteConfiguration, timeout: 2)

// host — exhaustive, so adding a case shows you where to handle it
channel.observe(AppSignal.self) { signal in … }
```

iOS gives third-party apps no XPC and no way to wake another app, so this is built from
the App Group plus a Darwin notification — the notification carries no payload, so the
signal name travels in the shared store and the notification rings the bell.

**Signals reach a running host only.** A signal sent to a suspended or terminated app is
lost rather than queued, which is why the buttons use the acknowledged form: without
waiting for the host to confirm, a press into a closed app would look exactly like a
successful one. A host that was foregrounded moments ago is still alive and does receive
them — that is what the demo shows — but one iOS has since suspended will not.

## Things to try

- **Toggle a flag in the companion, switch back to the host.** The value has changed. While
  the host is running it finds out through a Darwin notification, because
  `UserDefaults.didChangeNotification` does not fire for writes made by another process. It
  also re-reads on foreground, which covers the case where it was suspended and missed the
  notification.
- **Tap the reset arrow** next to an overridden flag. It falls back to the app's default and
  the badge disappears.
- **Show QR code**, then paste the scanned string into another device's **Import**. Only
  overrides travel, deflate-compressed.
- **Import something wrong** — paste `{"formatVersion":1,"values":{"nope":true}}`. It is
  rejected outright with a reason, rather than partly applied.
- **Watch the Combine counter.** The bottom section counts `$newOnboarding.publisher` as
  changes arrive, whether from the companion app or a remote payload.
- **Tap a signal button** in the companion, having just come from the demo app. It reports
  “handled”. Leave the demo closed, or wait for iOS to suspend it, and the same button
  reports that nothing answered.

## Files

| File | Target | Purpose |
|---|---|---|
| `DemoApp/AppFlags.swift` | host | The flag tree and the `FlagPole` that reads it |
| `DemoApp/ContentView.swift` | host | Live values, remote payloads, provenance, Combine |
| `DemoApp/DemoModel.swift` | host | Owns the pole and the remote source it feeds |
| `DemoApp/RemoteConfigurations.swift` | host | The bundled payloads |
| `DemoApp/AppSignals.swift` | both | The signal vocabulary, shared so both sides agree |
| `DemoApp/DemoApp.swift` | host | `@main`; publishes the schema on launch |
| `DemoCompanion/CompanionRootView.swift` | companion | Chooses which tabs the companion shows |
| `DemoCompanion/EnvironmentTab.swift` | companion | The one screen only this app can supply |
| `DemoCompanion/DemoCompanionApp.swift` | companion | `@main` |

`DemoApp` links **FeatureFlag** only. `DemoCompanion` also links **FeatureFlagUI**. No
editor code ships in the app people install.

Note how little the companion is. `CompanionRootView` is a list of tabs — overrides,
signals, flags, and the demo's own environment screen — because opening the shared store,
handling the two ways that fails, and the overrides, flags and signals screens all come
from `FlagCompanionView`. A companion with no signals and nothing bespoke needs no view
at all:

```swift
FlagCompanionView(appGroup: "group.com.andyyhope.featureflag.demo")
```

Everything except the two `@main` entry points also builds under `swift build`, as the
`DemoExamples` target, so the sources cannot silently rot.

## Running on a device

1. Set a `DEVELOPMENT_TEAM` on both targets and remove the ad-hoc signing overrides in
   `project.yml`.
2. Change the App Group in `project.yml`, `AppFlags.swift` and `CompanionRootView.swift` to
   one your team owns. All three must match.
3. `xcodegen generate` to rebuild the project.

The signing settings matter more than they look. With code signing switched **off** rather
than ad-hoc, entitlements are never embedded, the App Group container does not exist, and
the two apps silently share nothing.

## Adding remote overrides

`AppFlags` already declares remote keys. The framework decodes; fetching is yours:

```swift
let (data, _) = try await URLSession.shared.data(from: configURL)
try remote.apply(data, format: .json)
```

against a payload shaped like:

```json
{ "featureToggles": { "onboarding": { "v2": true },
                      "checkout": { "applePay": true } },
  "config": { "apiEndpoint": "https://staging.example.com" } }
```

Local overrides sit above remote in the stack, so anything set in the companion survives the
next fetch.
