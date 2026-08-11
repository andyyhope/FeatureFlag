import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct FeatureFlagPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FlagContainerMacro.self,
        FlagGroupMacro.self,
    ]
}
