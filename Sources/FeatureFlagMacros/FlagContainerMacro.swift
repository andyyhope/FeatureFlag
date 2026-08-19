import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct FlagContainerMacro {}

// MARK: - Members

extension FlagContainerMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: node, message: FlagContainerDiagnostic.structsOnly)
            )
            return []
        }

        let declarations = parse(declaration, in: context)
        let access = accessLevel(of: declaration)

        return [
            initialiser(for: declarations, access: access),
            descriptors(for: declarations, access: access),
        ]
    }

    /// The modifier generated members need to carry.
    ///
    /// `FlagContainer` is a public protocol, so a public container's generated members
    /// must be public too or they cannot satisfy it.
    private static func accessLevel(of declaration: some DeclGroupSyntax) -> String {
        for modifier in declaration.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open): return "public "
            case .keyword(.package): return "package "
            default: continue
            }
        }
        return ""
    }

    private static func initialiser(for declarations: [FlagDeclaration], access: String)
        -> DeclSyntax
    {
        let assignments = declarations.map { declaration -> String in
            switch declaration {
            case let .flag(flag):
                let remoteKey = flag.remoteKey.map { "remoteKey: \($0.trimmedDescription), " } ?? ""
                return """
                        _\(flag.propertyName) = FeatureFlag.Flag(
                            default: \(flag.defaultValue.trimmedDescription),
                            description: \(flag.description.trimmedDescription),
                            \(remoteKey)lookup: _lookup,
                            keyPath: _keyPrefix.appending("\(flag.propertyName)")
                        )
                    """

            case let .group(group):
                return """
                        \(group.propertyName) = \(group.containerType.trimmedDescription)(
                            _lookup: _lookup,
                            _keyPrefix: _keyPrefix.appending("\(group.propertyName)")
                        )
                    """
            }
        }

        return """
            \(raw: access)init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {
            \(raw: assignments.joined(separator: "\n"))
            }
            """
    }

    private static func descriptors(for declarations: [FlagDeclaration], access: String)
        -> DeclSyntax
    {
        let nodes = declarations.map { declaration -> String in
            switch declaration {
            case let .flag(flag):
                let type = flag.valueType.trimmedDescription
                return """
                            .flag(
                                FeatureFlag.FlagDescriptor(
                                    propertyName: "\(flag.propertyName)",
                                    keyPath: FeatureFlag.FlagKeyPath(["\(flag.propertyName)"]),
                                    description: \(flag.description.trimmedDescription),
                                    valueType: \(type).flagValueType,
                                    defaultValue: (\(flag.defaultValue.trimmedDescription) as \(type)).box,
                                    cases: FeatureFlag._flagValueCases(of: \(type).self),
                                    remoteKey: \(flag.remoteKey?.trimmedDescription ?? "nil"),
                                    recordShape: FeatureFlag._flagRecordShape(of: \(type).self)
                                )
                            )
                    """

            case let .group(group):
                let type = group.containerType.trimmedDescription
                return """
                            .group(
                                FeatureFlag.FlagGroupDescriptor(
                                    propertyName: "\(group.propertyName)",
                                    keyPath: FeatureFlag.FlagKeyPath(["\(group.propertyName)"]),
                                    description: \(group.description.trimmedDescription),
                                    children: \(type).flagDescriptors.map {
                                        $0.prefixed(by: "\(group.propertyName)")
                                    }
                                )
                            )
                    """
            }
        }

        return """
            \(raw: access)static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                [
            \(raw: nodes.joined(separator: ",\n"))
                ]
            }
            """
    }
}

// MARK: - Conformance

extension FlagContainerMacro: ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Empty when the type already declares the conformance itself.
        guard protocols.isEmpty == false else { return [] }

        // The member macro has already diagnosed this; adding a conformance the type
        // cannot satisfy would bury that message under follow-on errors.
        guard declaration.is(StructDeclSyntax.self) else { return [] }

        let extensionDeclaration: DeclSyntax = """
            extension \(type.trimmed): FeatureFlag.FlagContainer {}
            """
        return [extensionDeclaration.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Parsing

extension FlagContainerMacro {

    /// Reads the container's members in declaration order, skipping anything that is
    /// not a `@Flag` or `@FlagGroup` stored property.
    private static func parse(
        _ declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) -> [FlagDeclaration] {
        declaration.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return nil }

            guard let attribute = variable.flagAttribute else {
                // A stored property the generated initialiser has no way to set. Left
                // alone, this surfaces as "return from initializer without initializing
                // all stored properties", pointed into generated code the author never
                // wrote and never naming the property responsible. The commonest cause
                // is a nested container written without '@FlagGroup'.
                if variable.needsInitialisingByTheGeneratedInit {
                    context.diagnose(
                        Diagnostic(
                            node: variable,
                            message: FlagContainerDiagnostic.unattributedStoredProperty(
                                variable.firstPropertyName ?? "This property"
                            )
                        )
                    )
                }
                return nil
            }

            guard
                let binding = variable.storedBinding,
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else {
                context.diagnose(
                    Diagnostic(node: variable, message: FlagContainerDiagnostic.storedPropertyRequired)
                )
                return nil
            }

            guard let type = binding.typeAnnotation?.type else {
                context.diagnose(
                    Diagnostic(node: variable, message: FlagContainerDiagnostic.typeAnnotationRequired)
                )
                return nil
            }

            guard let description = attribute.argument(labelled: "description") else {
                context.diagnose(
                    Diagnostic(node: attribute, message: FlagContainerDiagnostic.descriptionRequired)
                )
                return nil
            }

            if attribute.identifier == "FlagGroup" {
                return .group(
                    FlagDeclaration.Group(
                        propertyName: identifier,
                        containerType: type,
                        description: description
                    )
                )
            }

            // Caught here rather than left to the conformance requirement, which fails as
            // "generic struct 'Flag' requires that 'String?' conform to 'FlagValue'" and
            // then points a second error into expanded code the author never wrote.
            if type.isOptional {
                context.diagnose(
                    Diagnostic(node: variable, message: FlagContainerDiagnostic.optionalUnsupported)
                )
                return nil
            }

            guard let defaultValue = attribute.argument(labelled: "default") else {
                context.diagnose(
                    Diagnostic(node: attribute, message: FlagContainerDiagnostic.defaultRequired)
                )
                return nil
            }

            return .flag(
                FlagDeclaration.Flag(
                    propertyName: identifier,
                    valueType: type,
                    defaultValue: defaultValue,
                    description: description,
                    remoteKey: attribute.argument(labelled: "remoteKey")
                )
            )
        }
    }
}

// MARK: - Diagnostics

enum FlagContainerDiagnostic: DiagnosticMessage {

    case structsOnly
    case typeAnnotationRequired
    case storedPropertyRequired
    case descriptionRequired
    case defaultRequired
    case optionalUnsupported

    /// Carries the property's name, because the whole point is to say which one.
    case unattributedStoredProperty(String)

    var message: String {
        switch self {
        case .structsOnly:
            return "'@FlagContainer' can only be applied to a struct"
        case .typeAnnotationRequired:
            return "flags need an explicit type annotation, for example 'var newOnboarding: Bool'"
        case .storedPropertyRequired:
            return "flags must be simple stored properties, without an initial value or accessors"
        case .descriptionRequired:
            return "flags need a 'description' so the companion app can explain them"
        case .defaultRequired:
            return "'@Flag' needs a 'default' value to fall back to"
        case .optionalUnsupported:
            return """
                flags cannot be optional: a flag always has a value, because 'default' \
                is what it falls back to. Use a sentinel the type already has, or an \
                enum with a case for 'unset'
                """
        case let .unattributedStoredProperty(name):
            return """
                '\(name)' has no '@Flag' or '@FlagGroup', so the generated initialiser \
                cannot set it. Add '@FlagGroup(description:)' if it is a nested \
                container, '@Flag(default:description:)' if it is a value, or give it a \
                default value if it is neither
                """
        }
    }

    /// The stable part of the identifier, since one case now carries a name.
    private var id: String {
        switch self {
        case .structsOnly: return "structsOnly"
        case .typeAnnotationRequired: return "typeAnnotationRequired"
        case .storedPropertyRequired: return "storedPropertyRequired"
        case .descriptionRequired: return "descriptionRequired"
        case .defaultRequired: return "defaultRequired"
        case .optionalUnsupported: return "optionalUnsupported"
        case .unattributedStoredProperty: return "unattributedStoredProperty"
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "FeatureFlagMacros", id: id)
    }
}


// MARK: - Optionality

extension VariableDeclSyntax {

    /// The name of the first thing this declares, for a message that has to say which.
    var firstPropertyName: String? {
        bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    /// Whether the generated initialiser has to set this, and cannot.
    ///
    /// Instance storage with no value of its own. A `static` belongs to the type, a
    /// computed property is derived, and one written with an initialiser Swift can set
    /// by itself — none of those leave the initialiser incomplete.
    var needsInitialisingByTheGeneratedInit: Bool {
        let isStatic = modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        guard isStatic == false else { return false }
        return bindings.contains { binding in
            binding.accessorBlock == nil && binding.initializer == nil
        }
    }
}

extension TypeSyntax {

    /// Whether this is `T?`, `T!` or `Optional<T>` — three spellings of one type.
    var isOptional: Bool {
        if self.is(OptionalTypeSyntax.self) { return true }
        if self.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return true }
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Optional"
        }
        return false
    }
}
