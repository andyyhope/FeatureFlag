# Sending signals to the host app

Telling a running app to *do* something — re-fetch its configuration, purge a cache —
from the companion.

## Overview

Flags are state. Some things are not: "re-fetch the remote config now" is a verb, and
there is no value to store for it.

``FlagSignalChannel`` carries those one way, from a companion app to its host. iOS gives
third-party apps no XPC and no way to wake another app, so this is built from the two
things that do cross the sandbox: an App Group both apps can read, and a Darwin
notification that carries no payload but does cross process boundaries. The signal name
goes in the shared store; the notification rings the bell.

### Declaring the signals

An enum, shared between both apps — a small file both targets compile, or a tiny module
they both import:

```swift
enum AppSignal: String, FlagSignal {
    case refetchRemoteConfiguration
    case purgeImageCache
    case signOut
}
```

Declaring it as an enum is what gives the host an exhaustive `switch`: add a case, and
the compiler shows you every place that has to handle it.

Give the cases readable labels by implementing `signalDescription`, which is what a
companion app puts on the button:

```swift
enum AppSignal: String, FlagSignal {
    case refetchRemoteConfiguration
    case purgeImageCache

    var signalDescription: String {
        switch self {
        case .refetchRemoteConfiguration: return "Re-fetch remote config"
        case .purgeImageCache: return "Purge image cache"
        }
    }
}
```

### Grouping them

One enum stops scaling the moment an app has more than a handful. File them by type:
each group is a real Swift boundary, so the host switches over one at a time and adding a
case tells you exactly where to handle it.

```swift
enum ConfigSignal: String, FlagSignal {
    case refetchRemoteConfiguration
    case clearRemoteConfiguration
}

enum CacheSignal: String, FlagSignal {
    case purgeImageCache
    case purgeEverything

    var requiresRestart: Bool { self == .purgeEverything }
}
```

The host observes each type it cares about, and each observer sees every signal
independently:

```swift
let config = channel.observe(ConfigSignal.self) { … }
let caches = channel.observe(CacheSignal.self) { … }
```

**Raw values have to be unique across every group.** A signal travels as its raw value
and nothing else, so two enums both defining `purge` would fire both observers for one
press. The companion refuses a set of groups that collide rather than picking one.

### Saying a signal needs a relaunch

A handled signal usually means something visibly changed. Some do not — purging a cache
the app read into memory at launch, or swapping a dependency built during start-up, is
done the moment the handler runs and invisible until the next launch:

```swift
var requiresRestart: Bool { self == .purgeEverything }
```

It changes nothing about delivery. It is there so the companion can report "handled —
relaunch to see it" rather than "handled", which is the difference between *nothing
happened* and *nothing happened yet*.

### Receiving, in the host

```swift
let channel = FlagSignalChannel(appGroup: "group.com.example.flags")!

let subscription = channel.observe(AppSignal.self) { signal in
    switch signal {
    case .refetchRemoteConfiguration: Task { await refetchConfiguration() }
    case .purgeImageCache: imageCache.removeAll()
    case .signOut: session.signOut()
    }
}
```

Hold the subscription for as long as you want delivery — releasing it stops delivery.
Handlers are called on the main queue.

### Sending, from the companion

```swift
channel.send(AppSignal.refetchRemoteConfiguration)
```

That form reports nothing, because a Darwin notification has no delivery receipt. When
the person pressing the button needs to know whether anything happened, wait for an
acknowledgement:

```swift
do {
    try await channel.send(AppSignal.refetchRemoteConfiguration, timeout: 2)
    // the host confirmed it handled this
} catch FlagSignalError.notAcknowledged {
    // it did not — see below
}
```

### Signals reach a running host only

A suspended or terminated app cannot receive a Darwin notification, and nothing in iOS
will wake it. A signal sent to an app that is not running is **lost, not queued**.

In practice that means switching apps to press the button is the problem. The host is
usually still running for a while after being backgrounded and will receive the signal;
once the system suspends it, nothing arrives. The example companion app handles this with
a delay — pick a signal, choose three seconds, switch to the host, and the signal fires
while it is in front of you.

``FlagSignalError/notAcknowledged`` is deliberately not called `hostNotRunning`. A missing
acknowledgement is also what you see if the host is running but slow, still launching, or
the notification was coalesced. Reporting it as certainty would be a lie the caller then
shows someone.

### Signals carry no payload

That is a limit on purpose rather than a feature not yet built. State belongs in flags,
which the companion can already edit. "Re-fetch for staging" is the `environment` flag
plus a bare `refetch` — set the flag, then send the signal — not a signal with an argument
and its own parallel way of describing values.

### Delivery details

Each signal gets a sequence number, and the host records the highest it has handled before
running the handler. A Darwin notification can arrive more than once for a single post,
and re-running "purge the cache" because the OS coalesced differently would be its own
kind of bug.

A signal this build cannot represent — a newer companion sending a case that does not
exist here — is skipped and deliberately left unacknowledged, so the sender learns it was
not handled rather than being told it was.
