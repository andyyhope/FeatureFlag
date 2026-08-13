# Remote overrides

Driving flags from a backend payload whose shape you do not control.

## Overview

``RemoteOverrideSource`` decodes; it never fetches. Your app gets configuration however it
likes — `URLSession`, a CDN, Firebase, a file in the bundle — and hands over the bytes:

```swift
let remote = RemoteOverrideSource(AppFlags.self)
let flags = FlagPole(AppFlags.self, sources: [local, remote])

let (data, _) = try await URLSession.shared.data(from: configURL)
try remote.apply(data, format: .json)
```

No networking, auth, retry or cache invalidation lives in a flag library. Those belong to
your app, where the timeouts and the token refresh already are.

### Saying where a flag lives in the payload

A backend's JSON rarely has the shape of your flag tree, so each flag says where to find
itself with `remoteKey`, read as a dot path:

```swift
@Flag(default: false, description: "Show the redesigned onboarding",
      remoteKey: "featureToggles.onboarding.v2")
var newOnboarding: Bool
```

```json
{
  "featureToggles": {
    "onboarding": { "v2": true }
  }
}
```

Paths index into arrays with a number, so `experiments.0.enabled` works:

```json
{ "experiments": [ { "enabled": true } ] }
```

**A flag with no `remoteKey` is not remotely overridable at all.** That is the safety
property: a flag only moves remotely if you said it could, so nothing your backend sends
can reach a flag you did not opt in.

### What a successful apply tells you

```swift
let result = try remote.apply(data, format: .json)

result.appliedKeys    // flags this payload set
result.absentKeys     // flags with a remoteKey the payload did not mention
```

`absentKeys` is the useful one when a rollout does not appear to be working. A flag in
that list fell through to whatever sits below the remote source, which usually means the
backend key changed or the path has a typo.

Applying replaces everything the source holds — it is not a merge. A flag the new payload
omits stops being remotely overridden. ``RemoteOverrideSource/clear()`` drops the lot.

### Strictness

Applying is all-or-nothing. Every value is checked against its flag's declared type, and
against the enum's cases where there are any, *before* anything is stored:

```swift
do {
    try remote.apply(data, format: .json)
} catch let RemoteOverrideError.rejected(problems) {
    for problem in problems {
        print(problem.remoteKey, problem.kind)   // .typeMismatch, .unknownCase, .unknownKey
    }
}
```

One bad field rejects the payload and reports *every* problem at once. The alternative —
applying what parsed and skipping the rest — leaves an app running on half a
configuration, which is the hardest kind of bug to reproduce.

Enum cases are checked because a backend sending `"platinum"` for a three-case enum would
otherwise fail silently at every read, looking exactly like a flag that does not work.

One deliberate allowance: JSON has a single number type, so a whole number satisfies a
`Double` flag. That is exact widening, not coercion — `"true"` is still not a `Bool`.

### Property lists

The same source reads a property list, which is convenient for configuration shipped in
the app bundle:

```swift
let data = try Data(contentsOf: bundleURL)
try remote.apply(data, format: .plist)
```

### When a path cannot express it

Some payloads are not addressable by path — a list of records where the flag name is a
field rather than a key:

```json
{
  "experiments": [
    { "name": "onboarding-v2", "state": "on" },
    { "name": "apple-pay",     "state": "off" }
  ]
}
```

Implement ``RemoteOverrideMapper``. It receives the decoded ``RemoteValue`` tree and the
``FlagSchema``, and returns raw values per flag key; validating them is still the source's
job, so a mapper never has to think about types or boxing:

```swift
struct ExperimentListMapper: RemoteOverrideMapper {

    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        guard case let .array(experiments)? = value.value(atPath: "experiments") else {
            throw RemoteOverrideError.malformed("expected an experiments array")
        }

        var states = [String: Bool]()
        for experiment in experiments {
            guard
                case let .string(name)? = experiment.value(atPath: "name"),
                case let .string(state)? = experiment.value(atPath: "state")
            else { continue }
            states[name] = state == "on"
        }

        return schema.flags.reduce(into: [:]) { result, entry in
            guard let remoteKey = entry.remoteKey, let state = states[remoteKey] else { return }
            result[entry.key] = .bool(state)
        }
    }
}

let remote = RemoteOverrideSource(AppFlags.self, mapper: ExperimentListMapper())
```

A mapper that returns a key no flag has is reported as
``RemoteOverrideProblem/Kind/unknownKey`` rather than ignored. ``DotPathMapper`` cannot
cause that — it only ever emits keys it read from the schema — but a custom mapper with a
typo can, and silently doing nothing would look exactly like a backend that sent no
overrides at all.

Worth knowing when you see it: this is the one problem kind that says something about
*your* code rather than the payload. Everything else in the list means the backend sent
something this build cannot use; `unknownKey` here means the mapper asked for a flag that
does not exist. The identically named case on ``FlagImportProblem`` is the ordinary data
version of the same idea — a document naming a flag this app does not have.

### Precedence

Put the remote source *below* local overrides:

```swift
FlagPole(AppFlags.self, sources: [userDefaults, remote])
```

A value someone set by hand then survives the next config refresh, which is what makes a
device usable for testing. Reverse the two and every refresh silently undoes the tester's
work.

### Key encoding has to agree

``RemoteOverrideSource`` builds its own ``FlagSchema``, so if the pole uses a non-default
encoding the source needs the same one — otherwise it validates against keys the pole
never looks up:

```swift
let remote = RemoteOverrideSource(AppFlags.self, keyEncoding: .snakecase)
let flags = FlagPole(AppFlags.self, sources: [remote], keyEncoding: .snakecase)
```
