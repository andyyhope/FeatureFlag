import SwiftSyntax

/// A `@Flag` or `@FlagGroup` property, parsed out of a container's member list.
enum FlagDeclaration {

    case flag(Flag)
    case group(Group)

    struct Flag {
        let propertyName: String
        let valueType: TypeSyntax
        let defaultValue: ExprSyntax
        let description: ExprSyntax
        let remoteKey: ExprSyntax?
    }

    struct Group {
        let propertyName: String
        let containerType: TypeSyntax
        let description: ExprSyntax
    }

    var propertyName: String {
        switch self {
        case let .flag(flag): return flag.propertyName
        case let .group(group): return group.propertyName
        }
    }
}

extension AttributeSyntax {

    /// The identifier of the attribute, e.g. `Flag` for `@Flag(default: false)`.
    var identifier: String? {
        attributeName.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// The expression passed for a labelled argument, if present.
    func argument(labelled label: String) -> ExprSyntax? {
        guard case let .argumentList(arguments) = arguments else { return nil }
        return arguments.first { $0.label?.text == label }?.expression
    }
}

extension VariableDeclSyntax {

    /// The `@Flag` or `@FlagGroup` attribute on this property, if it carries one.
    var flagAttribute: AttributeSyntax? {
        attributes
            .compactMap { $0.as(AttributeSyntax.self) }
            .first { $0.identifier == "Flag" || $0.identifier == "FlagGroup" }
    }

    /// The single binding of a simple stored property, or `nil` for anything else —
    /// computed properties, multiple bindings, or a property with an initial value.
    var storedBinding: PatternBindingSyntax? {
        guard bindings.count == 1, let binding = bindings.first else { return nil }
        guard binding.initializer == nil, binding.accessorBlock == nil else { return nil }
        return binding
    }
}
