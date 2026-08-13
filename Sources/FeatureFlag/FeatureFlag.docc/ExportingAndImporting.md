# Exporting and importing

Moving one device's overrides onto another, as a document or a QR code.

## Overview

"It only happens on my phone" is the question this answers. Export the overrides, send
them to whoever is trying to reproduce it, and their device is in the same state as yours.

Only overridden flags travel. Exporting every flag would mostly be a copy of the defaults
already compiled into the receiving app, and would not fit in a QR code.

### Exporting

```swift
let json = try flags.export(as: .json)
let plist = try flags.export(as: .plist)
```

The JSON is meant to be read and hand-edited:

```json
{
  "exportedAt" : "2026-01-01T09:41:00Z",
  "formatVersion" : 1,
  "values" : {
    "checkout.apple-pay" : true,
    "endpoint" : "https://staging.example.com/v3",
    "page-size" : 50
  }
}
```

Keys are sorted, and slashes are not escaped — a URL that reads `https:\/\/…` is not
hand-editable, whatever the specification permits.

### Importing

```swift
let result = try flags.importPayload(data, as: .json)
result.appliedKeys
```

Import is strict and all-or-nothing. If any key is unknown to this app, or holds a value
of the wrong type, **nothing** is applied and every problem is reported at once:

```swift
do {
    try flags.importPayload(data, as: .json)
} catch let FlagImportError.rejected(problems) {
    for problem in problems {
        print(problem.key, problem.kind)     // .unknownKey or .typeMismatch
    }
}
```

A document from a different app, or from a build where a flag has since changed type, is
refused rather than half-applied.

Values land in the highest-priority mutable source — the local override layer — so an
imported value outranks anything a backend later sends, and stays until it is cleared.

Import applies what it carries; it is not a wholesale replacement. Overrides the document
does not mention are left alone. Clear first if you want the document to be the whole
state:

```swift
try flags.removeAllOverrides()
try flags.importPayload(data, as: .json)
```

### QR codes

For handing state to someone sitting next to you, a code on screen beats a file:

```swift
let string = try flags.qrCodeString()      // "FFQR1:…"
let image = try flags.qrCodeImage()        // CGImage
```

The wire format is `FFQR1:` followed by base64url of a deflate-compressed payload.
Compression is what makes this practical: flag keys and JSON structure repeat heavily, so
realistic payloads shrink by an order of magnitude and fit where the raw JSON would not.

No camera UI ships here. Decoding takes whatever string your scanner produced:

```swift
try flags.importQRCode(scannedString)
```

A code that will not fit throws, and says what is in it so the message can be useful:

```swift
do {
    let string = try flags.qrCodeString()
} catch let FlagQRCodeError.payloadTooLarge(bytes, limit, overrideCount) {
    print("\(overrideCount) overrides is \(bytes) bytes; the limit is \(limit)")
}
```

The limit is 2,953 characters — the capacity of the largest QR code at the lowest error
correction level. Correction stays at that level on purpose: for a code shown on one
screen and scanned by another, capacity matters more than damage tolerance.

A scanned code is validated against this app's own flags exactly as a document is, so a
code from another app's build is rejected rather than partially applied.

### One thing worth knowing

**Export spans the whole stack.** ``FlagPole/overrides``, and everything built on it,
carries any value that is not the compiled default — *including* one a remote payload
supplied. Exporting from a device with remote configuration and importing elsewhere turns
those into local overrides on the receiving device.

That is usually what you want from "reproduce this device's state". It is worth knowing
before you share a code, because the receiving device will then hold those values against
its own backend's wishes until they are cleared.

### Errors you can hit while serialising

A `Double` flag holding infinity or NaN cannot be written as JSON. Handing one to
`JSONSerialization` raises an Objective-C exception Swift cannot catch, which would kill
the process, so ``FlagSerializationError/nonFiniteNumber(_:)`` is thrown first and names
the flag.
