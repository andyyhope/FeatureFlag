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
                                    remoteKey: \(flag.remoteKey?.trimmedDescription ?? "nil")
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
            guard
                let variable = member.decl.as(VariableDeclSyntax.self),
                let attribute = variable.flagAttribute
            else { return nil }

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

enum FlagContainerDiagnostic: String, DiagnosticMessage {

    case structsOnly
    case typeAnnotationRequired
    case storedPropertyRequired
    case descriptionRequired
    case defaultRequired

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
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "FeatureFlagMacros", id: rawValue)
    }
}
