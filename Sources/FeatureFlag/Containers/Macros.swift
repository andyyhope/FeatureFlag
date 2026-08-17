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

/// Turns a struct into a ``FlagRecord``, so a flag can hold a list of them.
///
/// ```swift
/// @FlagRecord
/// struct Endpoint {
///     var name: String
///     var url: URL
///     var enabled: Bool
/// }
///
/// @Flag(default: [Endpoint(name: "prod", url: …, enabled: true)], description: "Endpoints")
/// var endpoints: FlagRecords<Endpoint>
/// ```
///
/// Every stored property becomes a field, in declaration order, and must itself be a
/// ``FlagValue``. Fields are boxed one at a time rather than run through `Codable`, so a
/// `Date` inside a record is written exactly the way a `Date` flag beside it is written,
/// and an enum field arrives in the companion app as a picker.
///
/// Fields need explicit type annotations, for the same reason flags do.
/// The memberwise initialiser survives: the generated one lives in an extension,
/// because a struct that declares an initialiser in its own body loses it — and a
/// record you cannot construct is no use as a flag's default.
@attached(extension, conformances: FlagRecord, names: named(init(flagRecordBoxes:)))
@attached(member, names: named(flagRecordShape), named(flagRecordBoxes))
public macro FlagRecord() =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagRecordMacro")
