import SwiftSyntax
import SwiftSyntaxMacros

/// `@FlagRecordProperty(key:)` customises how a field is read from a payload, for
/// ``FlagRecordMacro`` to act on. It generates nothing itself.
///
/// `key:` is the name to read the field from when decoding a remote payload, for a
/// backend whose JSON key is not the Swift property name. It is decode-only: the record's
/// stored form stays keyed by the property name.
public struct FlagRecordPropertyMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
