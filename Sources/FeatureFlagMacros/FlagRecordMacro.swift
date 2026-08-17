import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Writes the boxing a ``FlagRecord`` would otherwise need by hand.
public struct FlagRecordMacro {}

// MARK: - Members

extension FlagRecordMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: FlagRecordDiagnostic.structsOnly))
            return []
        }

        let fields = parse(declaration) { context.diagnose($0) }

        guard fields.isEmpty == false else {
            context.diagnose(Diagnostic(node: node, message: FlagRecordDiagnostic.fieldsRequired))
            return []
        }

        let access = accessLevel(of: declaration)

        // The initialiser is deliberately not here — see the extension below.
        return [
            shape(for: fields, access: access),
            boxes(for: fields, access: access),
        ]
    }

    /// The modifier generated members need to carry.
    ///
    /// `FlagRecord` is a public protocol, so a public record's generated members must
    /// be public too or they cannot satisfy it.
    static func accessLevel(of declaration: some DeclGroupSyntax) -> String {
        for modifier in declaration.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open): return "public "
            case .keyword(.package): return "package "
            default: continue
            }
        }
        return ""
    }

    /// Shifts a generated block right, so what a reader sees in "Expand Macro" is laid
    /// out the way they would have written it.
    private static func indented(_ block: String, by spaces: Int) -> String {
        let padding = String(repeating: " ", count: spaces)
        return
            block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { padding + $0 }
            .joined(separator: "\n")
    }

    private static func shape(for fields: [RecordField], access: String) -> DeclSyntax {
        let entries = fields.map { field in
            """
            FeatureFlag.FlagRecordField(
                name: "\(field.name)",
                type: \(field.type).flagValueType,
                cases: FeatureFlag._flagValueCases(of: \(field.type).self)
            )
            """
        }

        return """
            \(raw: access)static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                [
            \(raw: indented(entries.joined(separator: ",\n"), by: 8))
                ]
            }
            """
    }

    private static func boxes(for fields: [RecordField], access: String) -> DeclSyntax {
        let entries = fields.map { "\"\($0.name)\": \($0.name).box" }

        return """
            \(raw: access)var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                [
            \(raw: indented(entries.joined(separator: ",\n"), by: 8))
                ]
            }
            """
    }

    static func initialiser(for fields: [RecordField], access: String) -> DeclSyntax {
        // One `guard` over every field rather than one per field: a record is all of
        // its fields or none of them, and a single statement says that plainly.
        let bindings = fields.map { field in
            "let \(field.name) = boxes[\"\(field.name)\"].flatMap(\(field.type).init(box:))"
        }
        let assignments = fields.map { "self.\($0.name) = \($0.name)" }

        return """
            \(raw: access)init?(flagRecordBoxes boxes: [String: FeatureFlag.FlagValueBox]) {
                guard \(raw: bindings.joined(separator: ",\n          ")) else {
                    return nil
                }
            \(raw: indented(assignments.joined(separator: "\n"), by: 4))
            }
            """
    }
}

// MARK: - Conformance

extension FlagRecordMacro: ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member macro has already diagnosed these; adding a conformance the type
        // cannot satisfy would bury that message under follow-on errors.
        guard declaration.is(StructDeclSyntax.self) else { return [] }

        let fields = parse(declaration, diagnose: { _ in })
        guard fields.isEmpty == false else { return [] }

        // The initialiser lives out here rather than among the members because a struct
        // that declares any initialiser in its own body loses the memberwise one Swift
        // would otherwise write — and a record you cannot construct is no use as a
        // flag's default. An extension keeps both.
        //
        // `protocols` is empty when the type already declares the conformance itself,
        // in which case the clause has to be left off or it reads as a redeclaration.
        let conformance = protocols.isEmpty ? "" : ": FeatureFlag.FlagRecord"

        let extensionDeclaration: DeclSyntax = """
            extension \(type.trimmed)\(raw: conformance) {
            \(initialiser(for: fields, access: accessLevel(of: declaration)))
            }
            """
        return [extensionDeclaration.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Parsing

/// One stored property of a record.
struct RecordField {
    let name: String
    let type: String
}

extension FlagRecordMacro {

    /// Reads the record's stored properties in declaration order.
    ///
    /// Diagnosis is a closure because the extension macro re-parses to decide whether
    /// to add a conformance, and reporting the same mistake twice helps nobody.
    static func parse(
        _ declaration: some DeclGroupSyntax,
        diagnose: (Diagnostic) -> Void
    ) -> [RecordField] {
        declaration.memberBlock.members.compactMap { member -> RecordField? in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return nil }

            // A record's shape is its instance storage. Statics belong to the type and
            // computed properties are derived, so neither is a field.
            guard variable.isInstanceStorage else { return nil }
            guard
                let binding = variable.bindings.first,
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else { return nil }

            guard let type = binding.typeAnnotation?.type else {
                diagnose(
                    Diagnostic(node: variable, message: FlagRecordDiagnostic.typeAnnotationRequired)
                )
                return nil
            }

            guard type.isOptional == false else {
                diagnose(
                    Diagnostic(node: variable, message: FlagRecordDiagnostic.optionalUnsupported)
                )
                return nil
            }

            return RecordField(name: name, type: type.trimmedDescription)
        }
    }
}

extension VariableDeclSyntax {

    /// Whether this declares instance storage: not `static`, not computed, and a single
    /// binding. A record built from anything else could not be rebuilt from its fields.
    var isInstanceStorage: Bool {
        let isStatic = modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        guard isStatic == false else { return false }
        guard bindings.count == 1, let binding = bindings.first else { return false }
        return binding.accessorBlock == nil
    }
}

// MARK: - Diagnostics

enum FlagRecordDiagnostic: String, DiagnosticMessage {

    case structsOnly
    case fieldsRequired
    case typeAnnotationRequired
    case optionalUnsupported

    var message: String {
        switch self {
        case .structsOnly:
            return "'@FlagRecord' can only be applied to a struct"
        case .fieldsRequired:
            return """
                '@FlagRecord' needs at least one stored property: a record is a shape, \
                and an empty one gives the editor nothing to show
                """
        case .typeAnnotationRequired:
            return "record fields need an explicit type annotation, for example 'var name: String'"
        case .optionalUnsupported:
            return """
                record fields cannot be optional: a field is either part of the shape or \
                it is not. Use a sentinel the type already has, or an enum with a case \
                for 'unset'
                """
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "FeatureFlagMacros", id: rawValue)
    }
}
