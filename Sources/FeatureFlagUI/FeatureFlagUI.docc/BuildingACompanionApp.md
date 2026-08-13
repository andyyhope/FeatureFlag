# Building a companion app

An editor for another app's flags, in about thirty lines.

## Overview

A companion app is an ordinary app that happens to edit somebody else's flags. It links
`FeatureFlagUI`, declares the same App Group as the host, and renders whatever schema it
finds there.

It does **not** link the host app's code, import its modules, or know its types. Change a
flag in the host, rebuild the host, and the companion picks it up — there is nothing to
keep in step.

### 1. Share an App Group

Add the **App Groups** capability to the companion target with the same identifier the
host uses. Without it the store cannot be built, and there is no way around that: the
group is what makes one app's `UserDefaults` visible to another.

### 2. Build a store

``FlagEditingStore`` is the whole model layer. Give it a group and it reads the host's
published schema and edits the same shared suite:

```swift
let store = try FlagEditingStore(appGroup: "group.com.example.flags")
```

It throws when the group is missing from *this* target's entitlements, and when the host
has not published a schema yet. Both are worth telling the user apart from an empty list,
because "run the host app once" is a fix they can act on:

```swift
struct CompanionRootView: View {

    private let store = try? FlagEditingStore(appGroup: "group.com.example.flags")

    var body: some View {
        if let store {
            FlagOverridesView(store: store)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "flag.slash").font(.largeTitle)
                Text("No flags yet").font(.headline)
                Text("Run the host app once so it can publish its schema.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
```

`ContentUnavailableView` would say this in one line, but it is iOS 17, and this package
supports iOS 16. Use it if your companion's own minimum is high enough — a companion is
an internal build, so it usually can be.

### 3. Put the screens in tabs

The two views answer different questions, and a companion of any size wants both. They
share one store, so state stays consistent between them:

```swift
struct CompanionRootView: View {

    let store: FlagEditingStore

    var body: some View {
        TabView {
            FlagOverridesView(store: store)
                .tabItem { Label("Overrides", systemImage: "slider.horizontal.3") }

            FlagBrowserView(store: store)
                .tabItem { Label("Flags", systemImage: "flag") }
        }
    }
}
```

``FlagOverridesView`` lists only what has been changed, with a per-row reset, the exported
JSON inline and copyable, and the actions that move overrides off the device — QR code,
share, import, reset everything.

``FlagBrowserView`` is the full tree. Groups are rows you push into, each showing how many
flags it holds and how many are overridden; searching flattens the whole tree, because
someone hunting for a key by name should not have to guess which group it was filed under.

Both views bring their own `NavigationStack`, so put them straight into a `TabView`
without wrapping them again.

### 4. That is the whole app

Everything else — which control a flag gets, how an enum becomes a picker, how a `Data`
flag is edited, what a reset does — comes from the schema and needs no work from you.

## Going further

### Editing something other than an App Group

The primary initialiser takes a schema and any `MutableFlagValueSource`, so
the same UI can edit a schema loaded from a file, a fixture in a test, or an in-memory
store in a preview:

```swift
let schema = try FlagSchema(contentsOfDirectory: exportedDirectory)
let store = FlagEditingStore(schema: schema, source: SnapshotSource(name: "Preview"))
```

That is also how to preview the editor with no App Group configured at all:

```swift
#Preview {
    FlagBrowserView(
        store: FlagEditingStore(
            schema: FlagSchema(
                flags: [
                    FlagSchema.Entry(
                        key: "new-onboarding",
                        propertyPath: ["newOnboarding"],
                        description: "Show the redesigned onboarding",
                        valueType: .bool,
                        defaultValue: .bool(false)
                    )
                ]
            ),
            source: SnapshotSource(name: "Preview")
        )
    )
}
```

### Building your own screens

The store exposes everything the built-in views use, so a custom editor is not a fork:

```swift
store.tree                      // the flag tree, rebuilt from the flat schema
store.sections                  // a flat, searchable grouping
store.overriddenKeys            // what has been changed
store.overriddenCount(in: node) // for a badge on a group row

store.value(for: entry)         // the value in effect
store.isOverridden(entry)
try store.setValue(.bool(true), for: entry)
try store.reset(entry)
try store.resetAll()
```

``FlagRowView`` renders one flag with the right control for its type, so you can build a
custom list and still not think about editors:

```swift
List {
    ForEach(store.tree.flags, id: \.key) { entry in
        FlagRowView(store: store, entry: entry)
    }
}
```

### Moving overrides on and off the device

The same transport the core module has, driven from the store:

```swift
let json = try store.export(as: .json)
let code = try store.qrCodeString()

try store.import(data, as: .json)
try store.importQRCode(scanned)
```

Import is strict and all-or-nothing, as everywhere else: one unknown key or wrong type
rejects the whole document rather than leaving a device on half a configuration.

### What the store will not show you

An override the host app would ignore is not displayed as an override. A shared suite can
hold a stale or hand-edited value of the wrong type, or an enum case this build no longer
has; the host skips those and falls back to its default, so the editor has to as well.

Showing it would be worse than useless — it would claim a value the app is quietly
ignoring, and bind a control to something it cannot render.

### Sending events as well as setting flags

Flags are state; some things are verbs. `FeatureFlag`'s `FlagEventChannel` carries
one-way instructions — "re-fetch the remote config", "purge the cache" — from the
companion to a running host. That is core-module API, usable from a companion without any
UI support: see `FeatureFlag`'s *Sending events to the host app* article.
