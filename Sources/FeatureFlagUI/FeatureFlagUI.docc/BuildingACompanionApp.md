# Building a companion app

An editor for another app's flags, in one line.

## Overview

A companion app is an ordinary app that happens to edit somebody else's flags. It links
`FeatureFlagUI`, declares the same App Group as the host, and renders whatever schema it
finds there.

It does **not** link the host app's code, import its modules, or know its types. Change a
flag in the host, rebuild the host, and the companion picks it up — there is nothing to
keep in step.

### The whole app

```swift
import FeatureFlagUI
import SwiftUI

@main
struct CompanionApp: App {
    var body: some Scene {
        WindowGroup {
            FlagCompanionView(appGroup: "group.com.example.flags")
        }
    }
}
```

That is not an abbreviation of the real thing — it *is* the app. ``FlagCompanionView``
opens the shared store, reports the two ways that can fail with a message someone can act
on, and gives you Overrides and Flags as tabs. None of it is specific to any host, so
none of it is worth writing twice.

Give the target the App Group described below and you are finished. The rest of this
article is for when you want more than the default.

### Sharing an App Group

Add the **App Groups** capability to the companion target with the same identifier the
host uses. Without it the store cannot be built, and there is no way around that: the
group is what makes one app's `UserDefaults` visible to another.

It is also the only thing the two apps share. The companion never links the host's code.

### Adding your own tabs

Some tabs only your app can supply — a screen built around one particular flag, or one
that sends your own `FlagSignal` cases. Pass a closure and you are handed
the loaded store, so you can order the built-in views however you like and put your own
beside them, without reimplementing loading or the failure states:

```swift
struct CompanionRootView: View {

    private enum Tab: Hashable {
        case overrides, signals, flags
    }

    @State private var selection: Tab = .overrides

    var body: some View {
        FlagCompanionView(appGroup: "group.com.example.flags") { store in
            TabView(selection: $selection) {
                FlagOverridesView(store: store)
                    .flagCompanionTab(
                        "Overrides", symbol: "dial.medium", isSelected: selection == .overrides
                    )
                    .tag(Tab.overrides)

                MySignalsTab()
                    .flagCompanionTab(
                        "Signals", symbol: "paperplane", isSelected: selection == .signals
                    )
                    .tag(Tab.signals)

                FlagBrowserView(store: store)
                    .flagCompanionTab(
                        "Flags", symbol: "flag", isSelected: selection == .flags
                    )
                    .tag(Tab.flags)
            }
        }
    }
}
```

`flagCompanionTab(_:symbol:isSelected:)` fills the symbol when its tab is selected and
outlines it otherwise. Two things it handles that are easy to get wrong: the symbol has
to ship a `.fill` variant — `slider.horizontal.3` and `dot.radiowaves.left.and.right` do
not, so a selected tab drawn with them looks like every other one — and iOS fills tab bar
glyphs for you, so the outline name alone changes nothing until `symbolVariants` is
cleared on the label itself.

### The two built-in screens

``FlagOverridesView`` lists only what has been changed, with a per-row reset, the exported
JSON inline and copyable, and the actions that move overrides off the device — QR code,
share, import, reset everything.

``FlagBrowserView`` is the full tree. Groups are rows you push into, each showing how many
flags it holds and how many are overridden; searching flattens the whole tree, because
someone hunting for a key by name should not have to guess which group it was filed under.

Both bring their own `NavigationStack`, so they go straight into a `TabView` without
wrapping them again.

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

### Sending signals as well as setting flags

Flags are state; some things are verbs. `FeatureFlag`'s `FlagSignalChannel` carries
one-way instructions — "re-fetch the remote config", "purge the cache" — from the
companion to a running host. That is core-module API, usable from a companion without any
UI support: see `FeatureFlag`'s *Sending signals to the host app* article.
