# Troubleshooting

The failures worth recognising on sight, and what each one actually means.

## Overview

Most of these are properties of the platform rather than bugs in the framework, which is
why they are documented rather than fixed.

### The two apps do not seem to share anything

Check that **both** targets declare the App Group and that the identifiers match exactly.
On the simulator there is a second cause: if code signing is disabled for the build, the
entitlements are never embedded, so no container exists. The example project signs
ad-hoc (`CODE_SIGN_IDENTITY = "-"`) for exactly this reason.

Do not rely on ``UserDefaultsSource/init(appGroup:name:)`` returning `nil` to tell you
this. It returns `nil` when the suite cannot be opened, but a group the target is not
entitled to use does not reliably produce that — on macOS it demonstrably does not — so
the failure shows up as writes going nowhere rather than as an obvious `nil`.

``FlagPole/publishSchema(appGroup:)`` is the reliable check. It goes through the
container URL, which iOS does check against the entitlements, and throws
``FlagSchemaError/notPublished`` when the group is not one this target may use.

### The companion says the host has not published a schema

``FlagSchema/init(appGroup:)`` throws ``FlagSchemaError/notPublished`` when
`flag-schema.json` is not in the shared container. Run the host app once — publishing
happens when *it* launches, not when the companion does.

If the host has run and it still fails, the two apps are not in the same group.

### A flag changed in the companion but the app did not react

Check in this order:

1. **Is the source the App Group one?** `UserDefaultsSource()` with no argument reads the
   app's own defaults, which the companion cannot see.
2. **Is the host running?** A suspended app cannot receive a Darwin notification. It
   re-reads on foreground, so bring it forward and look again.
3. **Is something above it in the stack winning?** Ask:

```swift
flags.resolution(for: flags.flags.$newOnboarding).sourceName
```

### A `Bool` flag reads back as a number, or the reverse

`UserDefaults` caches a key's CoreFoundation type within a process. If a key that has held
a number is then given a boolean, it still reads back as a number until the process
restarts — and no way of writing the boolean (`NSNumber`, `kCFBooleanTrue`, a plain `Any`)
avoids it. This was verified rather than assumed.

It only bites if a flag changes its Swift type while keeping its key, which is a breaking
change to that flag's meaning in any case. Give the new flag a new name.

### `@Flag` fails with "unknown attribute" or similar

Your module declares its own type called `Flag`, which shadows the attribute before any
macro runs. Qualify it:

```swift
@FeatureFlag.Flag(default: false, description: "Show the redesigned onboarding")
var newOnboarding: Bool
```

Everything the macro generates is already fully qualified, so nothing else can be
shadowed this way.

### `pole.someFlag` gives you something other than your flag

Real members win over dynamic member lookup. A flag named `flags`, `keys`, `schema`,
`overrides` or `descriptors` collides with a property of ``FlagPole`` itself, and the
shorthand quietly resolves to the pole's member instead of yours. Depending on the types
involved that is either a compile error at the use site or, worse, not an error at all.

Everything still works — reach it through the container:

```swift
pole.flags.schema        // your flag named "schema"
pole.schema              // the pole's FlagSchema
```

### "Flags must resolve to unique keys" on the first launch

Two flags encode to the same storage key. The message names both properties:

```
Flags must resolve to unique keys, but 'use-https-only' is claimed by
useHTTPSOnly and useHttpsOnly. Rename one of the properties, or use a
KeyEncoding that tells them apart.
```

There is no runtime remedy — both flags want the same storage, and letting one win
silently would mean the other never takes effect anywhere — so this traps when the schema
is built rather than later. Renaming a property is usually the fix.

The default encoding collides only when two names differ just in how an acronym is cased.
A custom ``KeyEncoding`` collides far more easily: anything that maps two distinct
property names onto one string will do it. ``FlagSchema/duplicateKeys`` reports them, so a
test can assert there are none.

### "flags cannot be optional"

`@Flag(default: nil, description: "…") var endpoint: String?` is rejected. A flag always
has a value: `default` is what it falls back to, and `nil` already means "no source
supplied one" at every layer beneath — `box(for:as:)` returning `nil` means *try the next
source*, and `setBox(nil, for:)` means *remove the override*. A flag whose value could be
`nil` would be indistinguishable from one nothing supplies.

Use a sentinel the type already has, or an enum with a case for unset:

```swift
@Flag(default: "", description: "Override the API host")
var apiHost: String

enum Endpoint: String, FlagValue, CaseIterable, FlagValueCases {
    case `default`, staging, local
}
```

Swift's own error — "generic struct 'Flag' requires that 'String?' conform to 'FlagValue'"
— appears alongside this one and cannot be suppressed: `@Flag` is a property wrapper, so
its constraint is checked whatever the macro says.

### "Return from initializer without initializing all stored properties"

A stored property the generated initialiser has no way to set. Almost always a nested
container written without `@FlagGroup`:

```swift
@FlagContainer
struct AppFlags {
    var checkout: CheckoutFlags        // needs @FlagGroup(description:)
}
```

From 0.6.0 this is reported at the property itself, naming it and listing the three
ways out — add `@FlagGroup`, add `@Flag`, or give the property a value of its own. On
an earlier build it surfaces pointed into expanded code, which is why it reads as
though the macro is broken rather than the declaration.

The same error from `@FlagRecord` means two fields sharing one declaration —
`var host: String, port: String`. Only the first would be generated for. Declare them
on separate lines.

### The macro complains about a missing type annotation

A macro sees syntax, not types, so it cannot infer one:

```swift
@Flag(default: false, description: "…")
var newOnboarding = false       // no

@Flag(default: false, description: "…")
var newOnboarding: Bool         // yes
```

### An error says nothing useful

It should not. Every error this framework throws carries a message that names the
flag, the value and what to do, through both `print(error)` and
`localizedDescription`.

If you are seeing "The operation couldn't be completed", you are on a build older
than 0.6.0.

### A remote payload appears to do nothing

Ask what the apply reported:

```swift
let result = try remote.apply(data, format: .json)
result.absentKeys        // declared a remoteKey, but the payload did not mention it
```

A flag in `absentKeys` fell through to whatever sits below the remote source. Usually the
backend key changed, or the dot path has a typo. A flag with no `remoteKey` at all is not
remotely overridable and will never appear in either list.

If nothing applied and it threw instead, ``RemoteOverrideError/rejected(_:)`` carries
every problem — one bad field rejects the whole payload by design.

### Importing throws `.rejected` with `.unknownKey`

The document was exported from a different app, or from a build where that flag has since
been renamed or removed. Import is all-or-nothing so an app never runs on half a
configuration; there is no partial-apply option, on purpose.

### A QR code will not encode

``FlagQRCodeError/payloadTooLarge(bytes:limit:overrideCount:)`` carries the override count
so you can say what to remove. Data flags are the usual culprit: base64 does not compress,
and one blob can exhaust the whole code. Export a document and share that instead.

### `FlagSignalChannel` reports `.notAcknowledged`

Usually the host is not running — signals reach a running app only, and nothing on iOS can
wake one. But it is also what you see if the host is slow, still launching, or the
notification was coalesced, so do not present it as certainty. See
[Sending signals to the host app](doc:SendingSignals).

### `FlagBrowserView` cannot be found on watchOS or tvOS

The module builds there but is empty: every view is behind `#if os(iOS) || os(macOS)`, so
the symbols do not exist. Those platforms have no `Menu`, `TextEditor` or bordered text
field, and a flag editor on a watch is not a real use case, so the module is scoped rather
than pretending. The core `FeatureFlag` module supports all four platforms.

### A record flag reads as its default, and the companion says "not a list of records"

A ``FlagRecords`` list is all of its records or none of them. One record missing a
field, or holding the wrong type in one, and the whole list is unreadable — so the flag
falls back to its default, silently, exactly as any other type mismatch does.

The usual causes are a store edited by hand, and a build that has added a field since
the stored value was written. The companion cannot produce one: it builds records from
the published shape.

Reset the flag to clear it. To see what is actually stored:

```swift
print(pole.$paymentMethods.resolution)
```

Give a new field an initialiser and this stops being a problem: a record stored before
the field existed is filled from it rather than rejected.

```swift
@FlagRecord
struct Endpoint {
    var name: String
    var weight: Int = 1     // added later, so it says what to assume
}
```

A field with no initialiser has nothing honest to fall back to, so a record missing one
is still refused. A field that is *present* but holds the wrong type is refused either
way — filling in an absent field is a migration, overwriting a wrong one would be
guessing.

### Everything reverts when a config refresh lands

The remote source is above the local one in the stack. Reverse them:

```swift
FlagPole(AppFlags.self, sources: [userDefaults, remote])
```

Local overrides belong on top, so a value set by hand survives the next refresh.
