/// Generates the wiring that turns a type into a ``FlagContainer``.
///
/// ```swift
/// @FlagContainer
/// struct AppFlags {
///     @Flag(default: false, description: "New onboarding")
///     var newOnboarding: Bool
///
///     @FlagGroup(description: "Checkout")
///     var checkout: CheckoutFlags
/// }
/// ```
///
/// Three things are added: conformance to ``FlagContainer``, an initialiser that binds
/// every flag beneath the container to a lookup, and a static `flagDescriptors` list
/// describing its shape. That last one is why FeatureFlag needs no runtime reflection —
/// a host can publish its schema without ever building a container.
///
/// Flags must carry an explicit type annotation, because a macro cannot infer types.
@attached(extension, conformances: FlagContainer)
@attached(member, names: named(init(_lookup:_keyPrefix:)), named(flagDescriptors))
public macro FlagContainer() =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagContainerMacro")

/// Nests one container inside another, namespacing its keys.
///
/// ```swift
/// @FlagGroup(description: "Checkout")
/// var checkout: CheckoutFlags
/// ```
///
/// Nesting is namespacing and nothing more: a group has no value of its own and never
/// gates the flags beneath it, so `checkout.applePay` is independent of everything
/// above it.
///
/// This expands to nothing on its own — ``FlagContainer()`` reads it for metadata.
@attached(peer)
public macro FlagGroup(description: String) =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagGroupMacro")
