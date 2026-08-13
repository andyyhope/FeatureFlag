# Observing changes

Reacting when a flag changes, whether the change came from this process or another one.

## Overview

There are two ways to watch a flag, and which you want depends on whether you are in
SwiftUI.

### In SwiftUI

``FlagPole`` is an `ObservableObject`. Observe it and any change to any flag re-renders:

```swift
struct ContentView: View {

    @ObservedObject var flags: FlagPole<AppFlags>

    var body: some View {
        VStack {
            if flags.newOnboarding {
                OnboardingView()
            }
            Text("Page size: \(flags.pageSize)")
        }
    }
}
```

`objectWillChange` is always delivered on the main thread, whichever thread the change
came from — including a companion app in another process.

### Everywhere else

Every flag has its own publisher, reached through the projected value:

```swift
flags.flags.$newOnboarding.publisher
    .removeDuplicates()
    .sink { isEnabled in
        analytics.setUserProperty("new_onboarding", value: isEnabled)
    }
    .store(in: &cancellables)
```

The publisher emits the current value immediately on subscription, then again whenever it
changes. That first send means a subscriber never has to read the flag separately to get
started.

Values arrive on whichever thread made the change. Add `.receive(on: DispatchQueue.main)`
if you need them somewhere specific:

```swift
flags.flags.checkout.$applePay.publisher
    .receive(on: DispatchQueue.main)
    .sink { showsApplePayButton = $0 }
    .store(in: &cancellables)
```

Note where the `$` goes. A group is a plain nested container with no projected value of
its own, so it is `checkout.$applePay`, not `$checkout.applePay`.

A publisher fires whenever the value *may* have changed — a source announcing a wholesale
change is one such moment. Add `.removeDuplicates()` when repeated identical values would
be a problem, as they would be for anything that logs or fetches.

### Changes from another process

A companion app writing an override is a different process writing the same suite. Two
things carry that across:

- **A Darwin notification**, posted on every write to an App Group source. This is what
  makes an edit appear in a running app within a moment.
- **A re-read on foreground**, because a suspended app cannot receive a Darwin
  notification and nothing will wake it to try.

Both are automatic when the source was built with
``UserDefaultsSource/init(appGroup:name:)``. Neither is available through
`UserDefaults.didChangeNotification`, which does not fire for writes made by another
process — the reason this plumbing exists at all.

You can force a re-read yourself if your app has some other moment it cares about:

```swift
source.refresh()
```

### Watching one thing rather than everything

`ObservableObject` on the pole is deliberately coarse: any flag changing invalidates
every view observing it. For a screen that reads one flag out of two hundred, take the
per-flag publisher instead and drive local state with it. For most apps the coarse
version is fine, and simpler.
