# Examples

Two apps that share one App Group: a host app that declares flags, and a companion app
that edits them without linking a line of the host's code.

Everything here except the two `@main` entry points is compiled by `swift build`, as the
`DemoExamples` target, so the sources cannot silently rot. The entry points are excluded
because a SwiftUI `App` needs a real Xcode app target.

## What each file is for

| File | Belongs to | Purpose |
|---|---|---|
| `DemoApp/AppFlags.swift` | host | The flag tree, and the pole that reads it |
| `DemoApp/ContentView.swift` | host | Shows live values and where each came from |
| `DemoApp/DemoApp.swift` | host | `@main`; publishes the schema on launch |
| `DemoCompanion/CompanionRootView.swift` | companion | Loads the schema, renders the editor |
| `DemoCompanion/DemoCompanionApp.swift` | companion | `@main` |

Note what the host app links: `FeatureFlag` only. No editor code ships in the app people
install.

## Building them in Xcode

1. Create two iOS App targets, `DemoApp` and `DemoCompanion`.
2. Add this package to both. `DemoApp` links **FeatureFlag**; `DemoCompanion` links
   **FeatureFlag** and **FeatureFlagUI**.
3. Add the files above to their respective targets.
4. Give **both** targets the same App Group capability, and change `demoAppGroup` in
   `AppFlags.swift` and `appGroup` in `CompanionRootView.swift` to a group your team
   owns. They must match, and the group must exist in your developer account.
5. Run `DemoApp` once so it publishes its schema, then run `DemoCompanion`.

Until the host has run at least once the companion has nothing to show — it has no other
way to learn what flags exist.

## Trying it out

- Toggle a flag in the companion. `DemoApp` updates **while running**, via a Darwin
  notification, because `UserDefaults.didChangeNotification` does not fire for writes
  made by another process.
- Background and foreground `DemoApp`. It re-reads then too, which covers the case where
  it was suspended and missed the notification.
- The "Where each value came from" section names the winning source, so you can see a
  local override beating a remote payload.
- Use **Show QR code** in the companion, then paste the scanned string into another
  device's **Import**. Only overrides travel, compressed, so realistic sets fit.

## Adding remote overrides

`AppFlags` already declares remote keys. The framework decodes; fetching is yours:

```swift
let remote = RemoteOverrideSource(AppFlags.self)
let pole = FlagPole(AppFlags.self, sources: [shared, remote])

let (data, _) = try await URLSession.shared.data(from: configURL)
try remote.apply(data, format: .json)
```

matching a payload shaped like:

```json
{ "featureToggles": { "onboarding": { "v2": true },
                      "checkout": { "applePay": true } },
  "config": { "apiEndpoint": "https://staging.example.com" } }
```

Applying is all-or-nothing: one mistyped field rejects the payload and reports every
problem, rather than leaving the app on half a configuration.
