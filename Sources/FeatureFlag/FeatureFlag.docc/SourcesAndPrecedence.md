# Sources and precedence

Stacking the places a value can come from, and finding out which one won.

## Overview

A ``FlagPole`` holds an ordered array of ``FlagValueSource``. Reading a flag asks each
source in turn and takes the first answer; if none has one, the flag reports its compiled
default.

**The order of the stack *is* the precedence.** There is no priority number to set and no
rule to remember beyond the order you wrote.

```swift
let flags = FlagPole(
    AppFlags.self,
    sources: [
        UserDefaultsSource(appGroup: "group.com.example.flags")!,   // 1. companion app
        RemoteOverrideSource(AppFlags.self),                        // 2. your backend
    ]
)
// 3. @Flag(default:)
```

That arrangement is the recommended one. A value set by hand stays set until it is
explicitly cleared, so a tester's device does not silently revert the moment a config
refresh lands. It is also what makes the companion app trustworthy: what you set is what
you get.

### The sources that ship

``UserDefaultsSource`` reads and writes `UserDefaults`, optionally an App Group suite
shared with a companion app:

```swift
UserDefaultsSource()                                            // this app's defaults
UserDefaultsSource(appGroup: "group.com.example.flags")!        // shared with a companion
```

Values are stored natively — a `Bool` flag is a real `Bool` in the suite — so `defaults
read`, other frameworks and older builds can all still make sense of them, and flags your
app already stores by hand are adopted as they are.

``SnapshotSource`` holds values in memory. It is the top of the stack in tests, the
landing place for an imported payload, and the easy way to force a value in a preview:

```swift
let local = SnapshotSource(name: "test")
let flags = FlagPole(AppFlags.self, sources: [local])

try local.setBox(.bool(true), for: "checkout.apple-pay")
flags.checkout.applePay     // true
```

``RemoteOverrideSource`` holds whatever the last backend payload said. It has its own
article: [Remote overrides](doc:RemoteOverrides).

### Layering a config per environment

An app that talks to more than one backend usually wants two config layers for the
environment it is in: one bundled with the build, and one fetched. ``EnvironmentConfiguration``
holds both and keeps them in step with the environment you switch to.

```swift
let config = EnvironmentConfiguration(
    AppFlags.self,
    local:  { env in Bundle.main.data(named: "\(env).json") },   // ships with the app
    remote: { env in try await api.fetchConfig(for: env) }       // fetched, async
)

let pole = FlagPole(AppFlags.self, sources: [byHand] + config.sources)

// when the environment flag changes:
await config.load(.staging)   // local staging.json, then remote staging.json
```

Precedence within the pair is **remote over local**, and ``EnvironmentConfiguration/sources``
returns them in that order — so the full stack, highest first, is a by-hand override, the
fetched config, the bundled config, then the compiled defaults.

Loading an environment clears each layer before it loads it, so a fetch that fails or
returns nothing falls back to the layer beneath — the bundled config, then the defaults —
rather than leaving an app labelled *staging* running the previous environment's values.
``EnvironmentConfiguration/load(_:)`` returns a ``LoadOutcome`` saying what happened to
each layer, since one can succeed while the other does not.

Drive it from the environment flag itself, so setting the environment to *staging* loads
staging's two layers:

```swift
pole.flags.$environment.publisher
    .removeDuplicates()
    .sink { environment in Task { await config.load(environment) } }
    .store(in: &cancellables)
```

Give that flag no `remoteKey`. A config could otherwise set the environment, which would
mean the app should have loaded a different config — and loading *that* could set it back.

The framework does no networking and reads no files: the two closures hand it the bytes,
it decodes, validates against the schema, and layers them. Each layer is an ordinary
``RemoteOverrideSource``, so you can audit either with a ``FlagMappingAudit`` before you
trust it.

### Setting and clearing overrides

Writes go to the highest-priority source that accepts them — the first
``MutableFlagValueSource`` in the stack:

```swift
try flags.setOverride(true, for: flags.flags.$newOnboarding)
try flags.removeOverride(for: flags.flags.$newOnboarding)
try flags.removeAllOverrides()
```

``FlagPole/removeAllOverrides()`` only touches flags this pole declares, so unrelated
values sharing the suite are left alone, and it skips flags that hold nothing rather than
writing blindly. On a large tree that is the difference between one write and hundreds,
each of which would broadcast a cross-process change.

If nothing in the stack is mutable, writing throws ``FlagError/noMutableSource``.

### Why is this flag false?

``FlagPole/resolution(for:)`` names the source that supplied the current value:

```swift
let resolution = flags.resolution(for: flags.flags.$newOnboarding)

resolution.sourceName    // "App Group", "Remote", or nil for the compiled default
resolution.box           // the value in effect
resolution.isDefault     // true when nothing overrode it
```

There is a second form taking a ``FlagKey`` and a ``FlagValueType`` instead of a typed
accessor. The generic form needs one call site per flag, which makes a diagnostics screen
— "where did every value come from?" — impossible to write as a loop:

```swift
for entry in flags.schema.flags {
    let resolution = flags.resolution(for: entry.key, as: entry.valueType)
    print(entry.key, resolution.sourceName ?? "default")
}
```

### Writing your own source

Three requirements: a name for diagnostics, a way to read a value, and a publisher that
says when things changed. Add ``MutableFlagValueSource`` if it accepts writes.

```swift
final class FirebaseSource: FlagValueSource, @unchecked Sendable {

    let sourceName = "Firebase"

    private let lock = NSLock()
    private let subject = PassthroughSubject<FlagChange, Never>()
    private var values: [FlagKey: FlagValueBox] = [:]

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    func refresh(with values: [FlagKey: FlagValueBox]) {
        lock.lock()
        self.values = values
        lock.unlock()
        subject.send(.all)
    }
}
```

The lock is not decoration. `@unchecked Sendable` is a promise you are making to the
compiler, and a pole reads flags from whatever thread the app happens to be on while your
network callback writes from another. Every source that ships here is written this way.

The `type` argument is the flag's declared type. A source stored in a loosely typed
medium can use it to decode exactly rather than guess — which is how
``UserDefaultsSource`` tells `1` from `true`, given that `UserDefaults` hands back
`NSNumber` for both.

Report ``FlagChange/keys(_:)`` when you know what changed and ``FlagChange/all`` when you
do not. `all` is correct but expensive: every observer re-reads everything.

### Reading from other threads

``FlagPole`` is not `@MainActor`. Reads are lock-protected and safe from any thread,
because apps read flags off the main thread constantly. Only `objectWillChange` is
delivered on the main thread, so SwiftUI observation stays correct.
