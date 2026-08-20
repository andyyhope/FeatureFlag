import SwiftSyntax
import SwiftSyntaxMacros

/// `@FlagRecordKey` marks the field that tells one record from another, for
/// ``FlagRecordMacro`` to read. It generates nothing itself.
///
/// It is an attribute on the field rather than an argument on `@FlagRecord` because a
/// key path cannot be written there: `\.name` has no context to infer its root from,
/// and `\Endpoint.name` is a circular reference to the type the macro is expanding.
public struct FlagRecordKeyMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
