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
        let key = keyField(among: fields) { context.diagnose(Diagnostic(node: node, message: $0)) }

        // The initialiser is deliberately not here — see the extension below.
        var members = [
            shape(for: fields, key: key, access: access),
            boxes(for: fields, access: access),
        ]
        if let key {
            members.append("\(raw: access)static var flagRecordKey: String? { \"\(raw: key)\" }")
        }
        return members
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

    /// The field marked `@FlagRecordKey`, if one is.
    private static func keyField(
        among fields: [RecordField],
        diagnose: (FlagRecordDiagnostic) -> Void
    ) -> String? {
        let keys = fields.filter(\.isKey).map(\.name)
        guard keys.count <= 1 else {
            diagnose(.oneKeyOnly(keys))
            return nil
        }
        return keys.first
    }

    private static func shape(
        for fields: [RecordField],
        key: String?,
        access: String
    ) -> DeclSyntax {
        let entries = fields.map { field in
            // An optional field has no decode fallback: absence is nil, not a default.
            // A required field casts the way `@Flag` casts a default, so the expression
            // always compiles given the annotation the field carries anyway.
            let fallback =
                field.isOptional
                ? "nil"
                : (field.defaultValue.map { "(\($0) as \(field.type)).box" } ?? "nil")
            let decodedName = field.decodedName.map { "\"\($0)\"" } ?? "nil"

            return """
                FeatureFlag.FlagRecordField(
                    name: "\(field.name)",
                    type: \(field.type).flagValueType,
                    cases: FeatureFlag._flagValueCases(of: \(field.type).self),
                    defaultValue: \(fallback),
                    fields: FeatureFlag._flagRecordShape(of: \(field.type).self),
                    isKey: \(field.name == key),
                    isOptional: \(field.isOptional),
                    decodedName: \(decodedName)
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
        // Built up rather than a dictionary literal so a nil optional field can be left
        // out entirely — there is no null to store, and an absent key reads back as nil.
        // Fields are read through `self` so a field named `boxes` cannot shadow the
        // accumulator, and an optional binds to a fixed `value` for the same reason.
        let entries = fields.map { field -> String in
            if field.isOptional {
                return "if let value = self.\(field.name) { boxes[\"\(field.name)\"] = value.box }"
            }
            return "boxes[\"\(field.name)\"] = self.\(field.name).box"
        }

        return """
            \(raw: access)var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                var boxes = [String: FeatureFlag.FlagValueBox]()
            \(raw: indented(entries.joined(separator: "\n"), by: 4))
                return boxes
            }
            """
    }

    static func initialiser(for fields: [RecordField], access: String) -> DeclSyntax {
        // One `guard` over every field rather than one per field: a record is all of
        // its fields or none of them, and a single statement says that plainly.
        // Subscripted through the parameter's own label rather than a short internal
        // name: a field called `boxes` would otherwise shadow the parameter inside the
        // guard, and fail as an error pointing into code nobody wrote. The only name
        // that can collide now is one that already collides with the generated
        // property of the same name.
        let required = fields.filter { $0.isOptional == false }
        let optional = fields.filter(\.isOptional)

        func binding(_ field: RecordField) -> String {
            """
            let \(field.name) = flagRecordBoxes["\(field.name)"]\
            .flatMap(\(field.type).init(box:))
            """
        }

        // Required fields go in one guard — a record is all of them or none. An optional
        // field binds outside it: an absent one reads back as nil, which is no failure.
        var body = [String]()
        if required.isEmpty == false {
            body.append("guard \(required.map(binding).joined(separator: ",\n      ")) else {")
            body.append("    return nil")
            body.append("}")
        }
        body.append(contentsOf: optional.map(binding))
        body.append(contentsOf: fields.map { "self.\($0.name) = \($0.name)" })

        return """
            \(raw: access)init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
            \(raw: indented(body.joined(separator: "\n"), by: 4))
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

        let access = accessLevel(of: declaration)

        let extensionDeclaration: DeclSyntax = """
            extension \(type.trimmed)\(raw: conformance) {
            \(initialiser(for: fields, access: access))
            }
            """

        return [
            extensionDeclaration.cast(ExtensionDeclSyntax.self),
            unavailableFlagValue(for: type, access: access).cast(ExtensionDeclSyntax.self),
        ]
    }

    /// A `FlagValue` conformance that exists only to be refused, in words.
    ///
    /// Declaring a record as a flag's type — `[Endpoint]`, or `Endpoint` on its own —
    /// otherwise fails as "Generic struct 'Flag' requires that 'Endpoint' conform to
    /// 'FlagValue'", which names a protocol the author has never heard of and says
    /// nothing about the type that does work. An unavailable conformance lets the
    /// compiler carry the sentence instead.
    ///
    /// Refusing it is also correct rather than merely convenient: a record boxed on its
    /// own would be a dictionary of mixed field types, which is the one shape
    /// `FlagValueType` cannot describe — the reason `FlagRecords` stores text at all.
    private static func unavailableFlagValue(
        for type: some TypeSyntaxProtocol,
        access: String
    ) -> DeclSyntax {
        """
        @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<\(type.trimmed)>' rather than '\(type.trimmed)' or '[\(type.trimmed)]'")
        extension \(type.trimmed): FeatureFlag.FlagValue {
            \(raw: access)static var flagValueType: FeatureFlag.FlagValueType {
                fatalError(
                    "\(type.trimmed) is a record: a flag holds FlagRecords<\(type.trimmed)>, not the record itself"
                )
            }
            \(raw: access)init?(box: FeatureFlag.FlagValueBox) {
                fatalError(
                    "\(type.trimmed) is a record: a flag holds FlagRecords<\(type.trimmed)>, not the record itself"
                )
            }
            \(raw: access)var box: FeatureFlag.FlagValueBox {
                fatalError(
                    "\(type.trimmed) is a record: a flag holds FlagRecords<\(type.trimmed)>, not the record itself"
                )
            }
        }
        """
    }
}

// MARK: - Parsing

/// One stored property of a record.
struct RecordField {
    let name: String

    /// The field's type. For an optional field this is the wrapped type — the type the
    /// value boxes and validates as, since absence is what carries the nil.
    let type: String

    /// Whether the field carries `@FlagRecordKey`.
    let isKey: Bool

    /// Whether the field is declared optional (`T?`). An optional field a payload omits
    /// or sends as `null` decodes to nil rather than failing the record, and nil is left
    /// out of the stored form.
    let isOptional: Bool

    /// The key to read the field from a payload, from `@FlagRecordProperty(key:)`, or
    /// `nil` to read by the property name. Decode-only.
    let decodedName: String?

    /// The expression it was written with, if any. `var weight: Int = 1` has one;
    /// `var name: String` does not.
    let defaultValue: String?
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

            // `var a: Int, b: Int` declares two fields in one breath, and only the
            // first would be generated for. Skipping the rest silently leaves the
            // initialiser incomplete, which surfaces as "return from initializer
            // without initializing all stored properties" pointed into generated code.
            guard variable.bindings.count == 1 else {
                diagnose(
                    Diagnostic(node: variable, message: FlagRecordDiagnostic.oneFieldPerLine)
                )
                return nil
            }

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

            let isOptional = type.isOptional
            // An optional field boxes and validates as its wrapped type; the shape
            // describes that underlying type, and absence carries the nil.
            let baseType =
                isOptional
                ? (type.optionalWrappedName ?? type.trimmedDescription.strippingOptionalWrapper)
                : type.trimmedDescription

            let isKey = variable.attributes.contains { attribute in
                attribute.as(AttributeSyntax.self)?.identifier == "FlagRecordKey"
            }

            // The key is what tells one record from another, so it has to be there in
            // every record — an optional key could be absent, leaving one unidentifiable.
            if isKey, isOptional {
                diagnose(
                    Diagnostic(node: variable, message: FlagRecordDiagnostic.keyCannotBeOptional)
                )
            }

            return RecordField(
                name: name,
                type: baseType,
                isKey: isKey,
                isOptional: isOptional,
                decodedName: variable.attributes.recordPropertyKey,
                defaultValue: binding.initializer?.value.trimmedDescription
            )
        }
    }
}

extension AttributeListSyntax {

    /// The `key:` of `@FlagRecordProperty(key:)` on this field, or `nil` when it has none
    /// — or the argument is not a plain string literal.
    var recordPropertyKey: String? {
        for attribute in self {
            guard let attribute = attribute.as(AttributeSyntax.self),
                attribute.identifier == "FlagRecordProperty",
                let expression = attribute.argument(labelled: "key"),
                let literal = expression.as(StringLiteralExprSyntax.self)
            else { continue }
            return literal.representedLiteralValue
        }
        return nil
    }
}

extension String {

    /// `Optional<T>` written out as `T`, for the one optional spelling the syntax tree
    /// does not expose a wrapped type for. Any other string is returned unchanged.
    var strippingOptionalWrapper: String {
        guard hasPrefix("Optional<"), hasSuffix(">") else { return self }
        return String(dropFirst("Optional<".count).dropLast())
    }
}

extension VariableDeclSyntax {

    /// Whether this declares instance storage: not `static`, not computed, and a single
    /// binding. A record built from anything else could not be rebuilt from its fields.
    var isInstanceStorage: Bool {
        let isStatic = modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        guard isStatic == false else { return false }
        // Every binding, so `var a: Int, b: Int` reaches the diagnostic that names it
        // rather than being dropped here without a word.
        return bindings.allSatisfy { $0.accessorBlock == nil }
    }
}

// MARK: - Diagnostics

enum FlagRecordDiagnostic: DiagnosticMessage {

    case structsOnly
    case fieldsRequired
    case typeAnnotationRequired
    case keyCannotBeOptional
    case oneFieldPerLine
    case oneKeyOnly([String])

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
        case .keyCannotBeOptional:
            return """
                a record's key cannot be optional: it is the field that tells one record \
                from another, so every record has to carry it
                """
        case .oneFieldPerLine:
            return """
                declare one field per line: '@FlagRecord' generates a shape entry and a \
                box for each one by name, and only the first of a shared declaration \
                would be written
                """
        case let .oneKeyOnly(names):
            return """
                a record has one key at most, and \(names.joined(separator: ", ")) are \
                all marked '@FlagRecordKey' — the key is the single field that tells one \
                record from another
                """
        }
    }

    /// The stable part of the identifier, since one case now carries a name.
    private var id: String {
        switch self {
        case .structsOnly: return "structsOnly"
        case .fieldsRequired: return "fieldsRequired"
        case .typeAnnotationRequired: return "typeAnnotationRequired"
        case .keyCannotBeOptional: return "keyCannotBeOptional"
        case .oneFieldPerLine: return "oneFieldPerLine"
        case .oneKeyOnly: return "oneKeyOnly"
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "FeatureFlagMacros", id: id)
    }
}
