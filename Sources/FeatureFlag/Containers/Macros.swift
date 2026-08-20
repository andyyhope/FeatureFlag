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
@attached(
    member,
    names: named(init(_lookup:_keyPrefix:)), named(flagDescriptors),
    named(flagContainerDescription)
)
public macro FlagContainer() =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagContainerMacro")

/// The same, with a line saying what this set of flags is for.
///
/// ```swift
/// @FlagContainer(description: "Everything the checkout team can turn on")
/// struct AppFlags { … }
/// ```
///
/// The companion shows it above the flags. The application name answers "whose flags
/// are these"; this answers "what are they", which is the question someone handed an
/// unfamiliar debug build actually has.
@attached(extension, conformances: FlagContainer)
@attached(
    member,
    names: named(init(_lookup:_keyPrefix:)), named(flagDescriptors),
    named(flagContainerDescription)
)
public macro FlagContainer(description: String) =
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
@attached(
    extension,
    conformances: FlagRecord, FlagValue,
    names: named(init(flagRecordBoxes:)), named(flagValueType), named(init(box:)), named(box)
)
@attached(
    member,
    names: named(flagRecordShape), named(flagRecordBoxes), named(flagRecordKey)
)
public macro FlagRecord() =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagRecordMacro")

/// Marks the field that tells one record from another.
///
/// ```swift
/// @FlagRecord
/// struct Endpoint {
///     @FlagRecordKey var name: String
///     var url: URL
/// }
///
/// flags.endpoints["staging"]?.url
/// ```
///
/// The key is what makes one record a different record rather than an edited one. Two
/// sharing it is a mistake with no correct behaviour — picking one silently would leave
/// the app running on a value nobody chose — so a list containing a duplicate is
/// unreadable and falls back to the flag's default, exactly as any other malformed
/// value does. A payload or a document carrying one is refused outright, naming the key.
///
/// It marks the field rather than being an argument on ``FlagRecord()`` because a key
/// path cannot be written there: `\.name` has no context to infer its root from, and
/// `\Endpoint.name` is a circular reference to the type being expanded.
///
/// This expands to nothing on its own — ``FlagRecord()`` reads it for metadata.
@attached(peer)
public macro FlagRecordKey() =
    #externalMacro(module: "FeatureFlagMacros", type: "FlagRecordKeyMacro")
