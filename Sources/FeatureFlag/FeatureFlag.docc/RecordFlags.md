# Records

A flag that holds a list of fixed-shape values, each field typed and each editable.

## Overview

Some configuration is not one value but a list of small structured ones: the payment
methods a checkout offers, the endpoints a build can talk to, the tiers a paywall
shows. A `[String: String]` loses the types and a JSON string loses everything, so
FeatureFlag has a shape for it.

```swift
@FlagRecord
struct PaymentMethod {
    var name: String
    var kind: PaymentKind
    var enabled: Bool
    var minimumSpend: Double
}

@FlagContainer
struct AppFlags {

    @Flag(
        default: [
            PaymentMethod(name: "Visa", kind: .card, enabled: true, minimumSpend: 0),
            PaymentMethod(name: "Apple Pay", kind: .wallet, enabled: true, minimumSpend: 5),
        ],
        description: "Payment methods offered at checkout"
    )
    var paymentMethods: FlagRecords<PaymentMethod>
}
```

Reading gives you your own type back:

```swift
for method in flags.paymentMethods.values where method.enabled {
    show(method.name)
}
```

### What `@FlagRecord` writes

Every stored property becomes a field, in declaration order. The macro generates the
shape, a box per field, and the way back from boxes to a record.

Each field must itself be a ``FlagValue`` — a field of some type that is not gets an
error where you wrote it. A field may be optional (`var minimumSpend: Double?`): a
payload that omits it, or sends it as `null`, reads it as `nil` rather than failing the
record, and a `nil` value is left out of the stored form rather than written as anything.
The record's key cannot be optional — it is what tells one record from another, so every
record has to carry it.

Fields are boxed one at a time rather than run through `Codable`. That matters more
than it sounds: `JSONEncoder` writes a `Date` as a number, so a date inside a record
would be stored differently from a date in the flag beside it. Going through the same
boxing as everything else means one wire format, and one set of round-trip tests
covering it.

The memberwise initialiser survives, because the generated one lives in an extension.
A struct that declares an initialiser in its own body loses the one Swift writes — and
a record you cannot construct is no use as a flag's default.

### Telling one record from another

Mark the field that identifies a record and it becomes the record's key:

```swift
@FlagRecord
struct Endpoint {
    @FlagRecordKey var name: String
    var url: URL
}

flags.endpoints["staging"]?.url
```

A key is what makes one record a *different* record rather than an edited one. Two
sharing it has no correct behaviour — picking one would leave the app running on a
value nobody chose — so a list containing a duplicate is unreadable and falls back to
the flag's default, exactly as any other malformed value does. A payload or a document
carrying one is refused outright, naming the key:

```
'config.endpoints' → endpoints: expected every record to have its own name,
got two with "staging"
```

The companion enforces the same rule rather than writing something the app will not
read: an edit that would collide is refused the way an unparseable one is, and "Add"
gives a new record a distinct key instead of a second empty one. The key also titles
each row, which is otherwise the first declared field and therefore a guess.

It marks the field rather than being an argument on `@FlagRecord` because a key path
cannot be written there — `\.name` has no context to infer its root from, and
`\Endpoint.name` is a circular reference to the type being expanded.

### A record is not a flag's type on its own

`FlagRecords<Endpoint>` is how a record reaches a flag. Neither `[Endpoint]` nor a bare
`Endpoint` works, and both say so:

```
conformance of 'Endpoint' to 'FlagValue' is unavailable: a record is stored as a list
— declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'
```

That is a refusal rather than a missing feature. A record boxed on its own would be a
dictionary of mixed field types, which is the one shape ``FlagValueType`` cannot
describe — and the reason a record list is stored as text at all.

### How it is stored

A list of records is stored as JSON text:

```json
[{"enabled":true,"kind":"card","minimumSpend":0,"name":"Visa"}]
```

To `UserDefaults`, to a property list, to a QR code, to import and export, and to
remote validation, the flag is a `String`. Nothing had to learn what a record is, and
nothing can drift.

What makes it more than a string is the **shape**, published beside it in the
``FlagSchema``:

```json
{ "key": "payment-methods",
  "valueType": "string",
  "recordShape": [
    { "name": "name", "type": "string" },
    { "name": "kind", "type": "string", "cases": ["card", "wallet"] },
    { "name": "enabled", "type": "bool" }
  ] }
```

`valueType` stays `"string"` on purpose. A companion app built before records existed
reads a type name it already understands and shows the JSON in a text field; a value
type it had never heard of would have made it reject the whole document and show
nothing at all.

### In the companion app

A record flag opens onto a list: add, duplicate by swiping from the leading edge,
reorder, remove. Each record opens onto a screen of its own, a row per field with the
control its type calls for — a toggle for a `Bool`, a date picker for a `Date`, and a
picker for an enum field, because the shape carries its cases.

The companion builds records from the shape, so it cannot write one the app will not
read — a new record starts every enum field on a real case rather than an empty string.
The FeatureFlagUI catalog's "Building a companion app" article covers the screens.

### From a backend

Give the flag a `remoteKey` and a payload can carry the shape a backend would write
anyway:

```swift
@Flag(default: [], description: "Endpoints", remoteKey: "config.endpoints")
var endpoints: FlagRecords<Endpoint>
```

```json
{ "config": { "endpoints": [
    { "name": "staging", "url": "https://staging.example", "weight": 7 }
] } }
```

Validation is as strict as everywhere else: a missing field, a field of the wrong type,
or an enum case this build has never heard of rejects the **whole payload** rather than
being found later as a flag that quietly stopped taking effect. A backend that sends the
list already serialised as a string is understood too, and held to the same standard.

### Matching a backend that is not shaped like your Swift

Two things a real payload often needs. A field the backend omits or sends as `null`:
declare it optional, and it reads as `nil` instead of failing the record. And a field
whose JSON key is not the property name: `@FlagRecordProperty(key:)` gives it the key to
read from.

```swift
@FlagRecord
struct PaymentMethod {
    @FlagRecordKey var name: String
    @FlagRecordProperty(key: "apple_pay") var applePay: Bool
    var minimumSpend: Double?          // absent or null → nil
}
```

```json
{ "config": { "paymentMethods": [
    { "name": "card", "apple_pay": false },
    { "name": "wallet", "apple_pay": true, "minimumSpend": 10 }
] } }
```

The custom key is **decode-only**: it applies when reading a payload, not to the record's
own stored form, which stays keyed by the property name. Once decoded a record is
canonical — the backend's key never appears in what is stored, exported, or shown in the
companion, and re-reading uses the property name.

### A field that is itself a list

A record's field can be another list of records:

```swift
@FlagRecord
struct SpendLimit {
    var currency: String
    var maximum: Double
}

@FlagRecord
struct PaymentMethod {
    var name: String
    var limits: FlagRecords<SpendLimit> = []
}
```

`FlagRecords` is a ``FlagValue``, so this always round-tripped — the nested list boxes
as a string inside its parent's JSON. What the shape adds is that it *describes* the
nested fields, so the companion pushes another list rather than showing a block of
escaped JSON, and a backend can send the shape it would write anyway:

```json
{ "name": "Visa", "limits": [ { "currency": "AUD", "maximum": 500 } ] }
```

A list already serialised as a string is still understood, since that is what an export
contains. One level of nesting is what the editor lays out well; deeper is representable
but reads as JSON.

### Adding a field later

Write the new field with an initialiser and lists already stored keep working:

```swift
@FlagRecord
struct Endpoint {
    var name: String
    var url: URL
    var weight: Int = 1     // added in a later build
}
```

The value goes into the shape, so a record written before the field existed — in the
store, in a backend's payload, or in an exported document — is filled from it rather
than refused. This is the same syntax and the same meaning as the default Swift's
memberwise initialiser already gives you.

A field with no initialiser has nothing to fall back to, so a record missing one is
still refused. And a field that is present but holds the wrong type is refused whether
it has a default or not: filling in an absent field is a migration, while overwriting a
wrong one would be guessing, and would hide a stored value that genuinely disagrees
with this build.

### When a stored list cannot be read

A list is all of its records or none of them. If one record is missing a field that has
no default, or holds the wrong type in one — a hand-edited store, say — the flag falls
back to its default, exactly as any other type mismatch does.

That fallback is silent in the app. The companion says so plainly rather than showing an
empty list, since an empty list would invite you to add a record and wonder why nothing
changed. See <doc:Troubleshooting>.

## Topics

### Declaring a record

- ``FlagRecord()``
- ``FlagRecordProperty(key:)``
- ``FlagRecord``
- ``FlagRecords``
- ``FlagRecordField``

### Related

- <doc:FlagValues>
- <doc:RemoteOverrides>
