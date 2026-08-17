# ``FeatureFlag``

Declare feature flags as Swift properties, read them type-safely, and edit them from a
separate companion app that never links a line of your code.

## Overview

A flag is a property. Declaring one gives you a typed read, a Combine publisher, a
description a companion app can display, and — if you want it — a path into whatever
shape your backend sends.

```swift
import FeatureFlag

@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

let flags = FlagPole(AppFlags.self, sources: [UserDefaultsSource()])

if flags.newOnboarding {
    // …
}
```

### The idea that makes it work

`@FlagContainer` generates `static var flagDescriptors` — a description of the flag tree
available **without an instance and without reflection**.

Everything else falls out of that. Your app writes those descriptors to a shared
container as a ``FlagSchema``; a companion app reads that document and renders an editor
for an app whose types it has never seen. One companion build works for any app that
publishes a schema. Remote key mapping, strict payload validation and editor selection
all read the same descriptors.

### Where to start

If you have never used the framework, read [Getting started](doc:GettingStarted) — it
goes from an empty project to a flag you can toggle from a second app.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:DeclaringFlags>
- ``FlagContainer()``
- ``Flag``
- ``FlagPole``

### Declaring flags

- <doc:FlagValues>
- <doc:RecordFlags>
- ``FlagGroup(description:)``
- ``FlagValue``
- ``FlagValueCases``
- ``FlagRecord()``
- ``FlagRecord``
- ``FlagRecords``
- ``FlagRecordField``
- ``KeyEncoding``

### Where values come from

- <doc:SourcesAndPrecedence>
- ``FlagValueSource``
- ``MutableFlagValueSource``
- ``UserDefaultsSource``
- ``SnapshotSource``
- ``FlagResolution``
- ``FlagError``

### Reacting to changes

- <doc:ObservingChanges>
- ``FlagAccessor``
- ``FlagChange``

### Remote configuration

- <doc:RemoteOverrides>
- ``RemoteOverrideSource``
- ``RemoteOverrideMapper``
- ``DotPathMapper``
- ``RemoteValue``
- ``RemoteApplyResult``
- ``RemoteOverrideProblem``
- ``RemoteOverrideError``

### Sharing flags with a companion app

- <doc:SharingWithACompanionApp>
- ``FlagSchema``
- ``FlagSchemaError``

### Moving overrides between devices

- <doc:ExportingAndImporting>
- ``FlagPayload``
- ``FlagPayloadFormat``
- ``FlagQRCode``
- ``FlagImportResult``
- ``FlagImportProblem``
- ``FlagImportError``
- ``FlagQRCodeError``
- ``FlagSerializationError``

### Sending signals to the host app

- <doc:SendingSignals>
- ``FlagSignal``
- ``FlagSignalChannel``
- ``FlagSignalSubscription``
- ``FlagSignalError``

### Keys and values

- ``FlagKey``
- ``FlagKeyPath``
- ``FlagValueBox``
- ``FlagValueType``

### Describing a container

- ``FlagContainer``
- ``FlagLookup``
- ``FlagDescriptor``
- ``FlagGroupDescriptor``
- ``FlagSchemaNode``

### Cross-process plumbing

- ``DarwinNotificationCenter``
- ``DarwinNotificationObserver``

### Fixing problems

- <doc:Troubleshooting>
