# Validating a remote config

Check, without running the app, that a config file wires up every flag it should.

## Overview

A large config file has too many values to trace by hand, and two ways for one to be
wrong that no single assertion catches.

A flag whose `remoteKey` matches nothing is **not an error** — it falls through to its
default, which looks exactly like a backend that sent no value. And a value in the file
that no flag reads is invisible until someone notices the feature never turned on.

``FlagMappingAudit`` reports both directions, from a payload and a container, with no
pole and no running app:

```swift
let json = try Data(contentsOf: configURL)
let audit = try FlagMappingAudit(AppFlags.self, applying: json)

print(audit)
// Flag mapping audit — incomplete.
//   absent (1) — a flag declares this path, the payload has nothing there:
//     • page-size
//   mismatched (1):
//     • 'config.tier' → checkout-tier: "gold" is not one of free, pro
//   unconsumed (2) — usually fine, often backend metadata — no flag reads these:
//     • config.page_size
//     • meta.version
//   41 of 43 remotely-overridable flags applied.
```

### The two directions

- **Absent** is the forward check: a flag declares a `remoteKey` the payload does not
  supply. Almost always a typo in the key — `config.page_size` where the flag reads
  `config.pageSize` — which is otherwise indistinguishable from a value the backend
  chose not to send.
- **Unconsumed** is the reverse: a value in the file that no flag reads. The same typo
  usually shows here too, as `config.page_size`, which is what makes it findable.

The audit never checks types itself. It reuses the validation
``RemoteOverrideSource`` applies, so a value it calls *applied* is one a real apply
would accept — and any type or enum-case problem arrives as a ``RemoteOverrideProblem``
in `mismatched`, the whole list at once rather than one per run.

### Unconsumed values usually are not faults

A real config carries metadata no flag reads — schema versions, build stamps, keys
another app shares the document for. So unconsumed values are reported but do **not**
fail the default audit:

```swift
XCTAssertTrue(audit.isComplete)          // absent + mismatched only
```

Ask for more when the file is yours alone:

```swift
audit.isComplete(strict: true)                     // every value must be read
audit.isComplete(strict: true, ignoring: ["meta"]) // …except under meta.*
```

### In a test

Add `FeatureFlagTestSupport` to your **test target** — never an app target, since it
links XCTest — for a call-site assertion:

```swift
import FeatureFlagTestSupport

func testStagingConfigMapsEveryFlag() throws {
    let json = try Data(contentsOf: Bundle.module.url(forResource: "staging", withExtension: "json")!)
    XCTAssertFlagsFullyMapped(AppFlags.self, applying: json, strict: true, ignoring: ["meta"])
}
```

The failure is the whole report, so a large file surfaces all of its problems in one
run.

Without the helper, the audit is framework-agnostic:

```swift
let audit = try FlagMappingAudit(AppFlags.self, applying: json)
XCTAssertTrue(audit.isComplete, "\(audit)")   // any test framework
try audit.requireComplete(strict: true, ignoring: ["meta"])  // throws the report
```

`requireComplete` also suits a one-off check at launch in a debug build.

### A record flag reads a whole subtree

A record list's `remoteKey` names a subtree — `config.endpoints` — and every leaf
beneath it counts as read, so a keyed list of a hundred endpoints does not show as a
hundred unconsumed values.

### A note on custom mappers

Reverse coverage is computed from the flags' declared `remoteKey` paths, so it reflects
``DotPathMapper``. A custom ``RemoteOverrideMapper`` that reads the payload some other
way makes `unconsumed` advisory rather than exact; `absent` and `mismatched` stay
accurate, since those come from what the mapper actually produced.

## Topics

### Auditing

- ``FlagMappingAudit``
- ``FlagMappingAuditError``
