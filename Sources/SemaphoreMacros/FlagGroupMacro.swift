import SwiftSyntax
import SwiftSyntaxMacros

/// `@FlagGroup` carries metadata for ``FlagContainerMacro`` to read and generates
/// nothing itself, leaving the property as a plain stored declaration that the
/// generated initialiser assigns.
public struct FlagGroupMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
