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

## Remote configuration, without a backend

The framework decodes; it never fetches. `DemoApp` ships three payloads that stand in for
what your app would download, so the whole path runs on a simulator with no network:

| Payload | What it shows |
|---|---|
| **Staging rollout** | Dot-path mapping — `featureToggles.onboarding.v2` finds `new-onboarding` |
| **Killswitch** | A backend turning things off, and a companion override outranking it |
| **Malformed payload** | One bad field rejects the whole thing; the valid field beside it is *not* applied |

The most instructive sequence: set Apple Pay in the companion, come back, apply
**Killswitch**. The flag stays on, and "Where each value came from" says `Companion`.
Clear the override and it flips to `Remote`. That is the source ordering doing its job.

`Tests/DemoExamplesTests` checks these payloads against the real flag tree, because a
mistyped dot path fails silently as "the backend sent nothing" — the exact bug the demo
exists to make visible.

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

## Files

| File | Target | Purpose |
|---|---|---|
| `DemoApp/AppFlags.swift` | host | The flag tree and the `FlagPole` that reads it |
| `DemoApp/ContentView.swift` | host | Live values, remote payloads, provenance, Combine |
| `DemoApp/DemoModel.swift` | host | Owns the pole and the remote source it feeds |
| `DemoApp/RemoteConfigurations.swift` | host | The bundled payloads |
| `DemoApp/DemoApp.swift` | host | `@main`; publishes the schema on launch |
| `DemoCompanion/CompanionRootView.swift` | companion | Loads the schema, renders the editor |
| `DemoCompanion/DemoCompanionApp.swift` | companion | `@main` |

`DemoApp` links **FeatureFlag** only. `DemoCompanion` also links **FeatureFlagUI**. No
editor code ships in the app people install.

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
