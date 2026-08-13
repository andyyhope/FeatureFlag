# Declaring flags

Containers, nesting, the keys values are stored under, and reading a flag with no pole
behind it.

## Overview

Everything starts with a type annotated with `@FlagContainer`. The macro adds three
things: conformance to ``FlagContainer``, an initialiser that binds every flag beneath it
to a lookup, and `static var flagDescriptors` — the container's shape, available without
building one.

That last one is why nothing here needs runtime reflection, and why a companion app can
render your flags without linking your code.

### Declaring a flag

```swift
@FlagContainer
struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}
```

Two rules the compiler will hold you to:

- **The type annotation is required.** A macro sees syntax, not types, so
  `var newOnboarding = false` cannot work. Leave it off and the macro says so.
- **`description` is required.** It is the label in the companion app's list. A flag
  nobody can identify is a flag nobody dares change.

`remoteKey` is optional, and says where this flag lives in a backend payload. A flag
without one is not remotely overridable at all — see
[Remote overrides](doc:RemoteOverrides).

```swift
@Flag(default: false, description: "Show the redesigned onboarding",
      remoteKey: "featureToggles.onboarding.v2")
var newOnboarding: Bool
```

### Nesting

`@FlagGroup` nests one container inside another:

```swift
@FlagContainer
struct AppFlags {

    @FlagGroup(description: "Checkout")
    var checkout: CheckoutFlags
}

@FlagContainer
struct CheckoutFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool

    @FlagGroup(description: "Express")
    var express: ExpressFlags
}

@FlagContainer
struct ExpressFlags {

    @Flag(default: false, description: "One-tap purchase")
    var oneTap: Bool
}
```

Reading follows the shape you declared, and so does the key:

```swift
flags.checkout.express.oneTap        // stored under "checkout.express.one-tap"
```

**Nesting is namespacing and nothing else.** A group has no value of its own and never
gates the flags beneath it. `checkout.express.oneTap` is true or false entirely on its
own account, whatever `checkout` contains. There is no evaluation order to hold in your
head, and no way to accidentally disable a subtree.

### Keys

Property names become keys through a ``KeyEncoding``. The default is `kebabcase`, applied
to each path component separately so nesting always survives intact:

| Encoding | `checkout.express.oneTap` becomes |
|---|---|
| `.kebabcase` (default) | `checkout.express.one-tap` |
| `.snakecase` | `checkout.express.one_tap` |
| `.verbatim` | `checkout.express.oneTap` |

```swift
let flags = FlagPole(AppFlags.self, sources: [source], keyEncoding: .snakecase)
```

Word splitting handles acronyms and digits the way you would write them by hand:
`useHTTPSOnly` becomes `use-https-only`, and `checkoutV2` becomes `checkout-v2`.

Write your own if you have an existing key convention to match:

```swift
let screaming = KeyEncoding(separator: "__") { $0.uppercased() }
```

**An encoding has to keep every property distinct.** The one above does not: `oneTap` and
`onetap` both become `ONETAP`. Two flags landing on one key is a declaration mistake with
no runtime remedy — both want the same storage, and letting one quietly win would mean the
other never takes effect — so building the pole traps immediately, naming both properties.
It happens with the default encoding too: `useHTTPSOnly` and `useHttpsOnly` are both
`use-https-only`.

``FlagSchema/duplicateKeys`` reports them if you would rather assert in a test than find
out on first launch:

```swift
XCTAssertTrue(FlagSchema(AppFlags.self).duplicateKeys.isEmpty)
```

Choose an encoding once, at the start. Changing it later renames every key, which means
every stored override — on every tester's device — stops being found.

### Reading metadata off a flag

The projected value, reached with `$`, is a ``FlagAccessor``. It carries everything the
flag knows about itself:

```swift
let flag = flags.flags.$newOnboarding

flag.key            // "new-onboarding"
flag.description    // "Show the redesigned onboarding"
flag.defaultValue   // false
flag.remoteKey      // "featureToggles.onboarding.v2"
flag.currentValue   // what it resolves to right now
flag.publisher      // AnyPublisher<Bool, Never>
```

Note the two dots: `flags` is the pole, `flags.flags` is the container. The shorthand
`flags.newOnboarding` reads the value, but a projected value is not reachable that way.

### Flags without a pole

A `@Flag` declared with no lookup behind it always reports its default. Nothing has to be
wired up, which is what makes previews and quick tests work with no setup at all:

```swift
struct OnboardingPreviewFlags {

    @Flag(default: true, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}

OnboardingPreviewFlags().newOnboarding      // true, with no pole anywhere
```

When a test needs a specific value rather than the default, put a ``SnapshotSource`` on
top instead — see [Sources and precedence](doc:SourcesAndPrecedence).

### Public containers

The macro matches the access level of the type it is attached to, so a container in a
framework can be `public` and everything generated with it stays consistent:

```swift
@FlagContainer
public struct AppFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    public var newOnboarding: Bool
}
```

### If your module already has a type called `Flag`

A local `Flag` shadows the attribute, and the failure happens before any macro runs.
Qualify it:

```swift
@FeatureFlag.Flag(default: false, description: "Show the redesigned onboarding")
var newOnboarding: Bool
```

Everything the macro generates is already fully qualified, so nothing else in the
framework can be shadowed this way.
