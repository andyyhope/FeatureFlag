# Flag values

The types a flag can hold, and how to add your own.

## Overview

A flag can be any type conforming to ``FlagValue``. Eight primitives conform already,
along with arrays and string-keyed dictionaries of them, and any `RawRepresentable` whose
raw value is itself a flag value — which covers most enums for free.

Everything is stored through one canonical representation, ``FlagValueBox``. That is what
lets a single value travel through `UserDefaults`, JSON, a property list and a QR code
without four separate encodings to keep in agreement.

### The built-in types

```swift
@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "A switch")
    var enabled: Bool

    @Flag(default: 20, description: "A count")
    var pageSize: Int

    @Flag(default: 0.5, description: "A ratio")
    var rolloutShare: Double

    @Flag(default: 1.0, description: "A ratio, smaller")
    var scale: Float

    @Flag(default: "beta", description: "A name")
    var channel: String

    @Flag(default: Data(), description: "A blob")
    var payload: Data

    @Flag(default: .distantPast, description: "A moment")
    var launchesAt: Date

    @Flag(default: URL(string: "https://example.com")!, description: "An endpoint")
    var endpoint: URL
}
```

`URL` is stored as its string form rather than an archived blob, so a shared suite stays
readable with `defaults read` and portable between builds.

### Collections

Arrays and string-keyed dictionaries work as long as their elements do:

```swift
@Flag(default: [], description: "Markets to enable")
var markets: [String]

@Flag(default: [:], description: "Per-market rollout share")
var rolloutByMarket: [String: Double]
```

Dictionaries must be keyed by `String`. Property lists and JSON have no other kind of
key, and a flag that cannot survive a trip through either would not be editable from a
companion app.

### Enums

An enum with a raw value conforms with no implementation at all:

```swift
enum Tier: String, FlagValue {
    case free, pro, enterprise
}

@Flag(default: Tier.free, description: "Pricing tier to present")
var tier: Tier
```

Add `CaseIterable` and ``FlagValueCases`` and the flag becomes a picker in the companion
app instead of a free-text field, because the schema then carries the list of cases:

```swift
enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro, enterprise
}
```

That list is also enforced. A remote payload sending `"platinum"` is rejected outright
rather than silently falling back to the default on every read — the difference between
a backend error you can see and a flag that mysteriously never takes effect.

An `Int`-raw enum works the same way:

```swift
enum RetryPolicy: Int, FlagValue, CaseIterable, FlagValueCases {
    case none = 0, once = 1, aggressive = 3
}
```

### Conforming your own type

Implement ``FlagValue`` directly when a type is not `RawRepresentable`. Three
requirements: the ``FlagValueType`` it stores as, how to build one from a box, and how to
make a box from one.

```swift
struct Percentage: FlagValue {

    var amount: Double

    static var flagValueType: FlagValueType { .double }

    init(amount: Double) {
        self.amount = amount
    }

    init?(box: FlagValueBox) {
        guard case let .double(value) = box else { return nil }
        self.init(amount: value)
    }

    var box: FlagValueBox { .double(amount) }
}
```

Returning `nil` from `init?(box:)` is how a value refuses a stored representation it
cannot make sense of. The flag then falls through to the next source, and finally to its
default — a malformed store should never crash a running app.

Keep the stored form simple. Whatever you choose has to be legible in a shared
`UserDefaults` suite and editable in a companion app that only knows it as a `Double`.

### Reading and writing boxes directly

Most code never touches ``FlagValueBox``. Import, export and the companion app all do,
because they work from a schema rather than from your Swift types:

```swift
let box = FlagValueBox.bool(true)
box.matches(.bool)          // true
Bool(box: box)              // true
```
