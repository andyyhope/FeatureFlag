# Sharing flags with a companion app

Publishing a schema so a second app can edit your flags without linking your code.

## Overview

A companion app is a separate binary. It can read an App Group's `UserDefaults`, but it
has no idea what your flag tree *is* — what exists, what it is called, what type it holds,
or which values an enum allows.

So the host publishes a ``FlagSchema``: a JSON description of the tree, complete enough
for an editor to be rendered from it alone. That document is what decouples the UI. One
companion build can edit any app that publishes one.

### Setting it up

Both targets need the **App Groups** capability with the same identifier. Then, in the
host, point the source at the group and publish on launch:

```swift
let flags = FlagPole(
    AppFlags.self,
    sources: [UserDefaultsSource(appGroup: "group.com.example.flags")!]
)

try flags.publishSchema(appGroup: "group.com.example.flags")
```

Publish every launch, not once. The schema describes the build that is running, and a
build with a new flag needs to say so.

``FlagPole/publishSchema(appGroup:)`` throws ``FlagSchemaError/notPublished`` when the
container cannot be reached — which on iOS means the group is missing from the target's
entitlements. Unsandboxed macOS performs no such check and hands back a constructed path
regardless, so treat a success there as less informative than one on device.

There is also a directory form, which is what tests and macOS tools use:

```swift
try flags.publishSchema(inDirectory: someDirectory)
```

### What the schema carries

Per flag: the storage key, the property path, the description, the value type, the
compiled default, the enum's cases if it has any, and the remote key. Per group: its
property path and description, so the editor can label its sections and nest them.

```json
{
  "formatVersion": 1,
  "generatedAt": "2026-01-01T00:00:00Z",
  "applicationName": "Demo",
  "flags": [
    {
      "key": "checkout.apple-pay",
      "propertyPath": ["checkout", "applePay"],
      "description": "Offer Apple Pay",
      "valueType": "bool",
      "defaultValue": false
    }
  ],
  "groups": [
    { "propertyPath": ["checkout"], "description": "Checkout" }
  ]
}
```

`applicationName` defaults to the bundle's display name, so a companion that can see more
than one app has something readable to head the list with. Pass your own if you want
something else:

```swift
FlagPole(AppFlags.self, sources: sources, applicationName: "Demo (Staging)")
```

### Reading it back

```swift
let schema = try FlagSchema(appGroup: "group.com.example.flags")

schema.flags.count
schema.valueTypes           // [FlagKey: FlagValueType], for validating a payload
```

This is what the `FeatureFlagUI` module builds its editor from. If you are writing the
companion, start at that module's documentation instead — it has the views already.

### What it costs

Everything the editor shows has to survive a trip through JSON. A flag's Swift type is
gone by the time the companion sees it; what remains is a ``FlagValueType``, which is why
custom ``FlagValue`` types are edited as whatever they store as. A `Percentage` backed by
a `Double` is a number field in the companion, not a percentage field.

That is the trade for a companion app you build once, and it is deliberate.

### Getting changes back into the running app

`UserDefaults.didChangeNotification` does **not** fire for writes made by another process,
so the companion's edit would otherwise sit in the suite unnoticed until your next launch.
Two mechanisms carry it:

- A **Darwin notification** posted on every write, named from the App Group identifier.
  This is what makes an edit appear in a running app within a moment.
- A **re-read on foreground**, which covers the case where your app was suspended and
  could not receive one.

Both come for free with ``UserDefaultsSource/init(appGroup:name:)``. Neither can wake a
terminated app — nothing on iOS can — so a change made while your app is gone lands the
next time it launches, which is exactly what you want from a stored override.
