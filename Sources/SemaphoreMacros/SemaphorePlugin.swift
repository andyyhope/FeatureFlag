import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SemaphorePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = []
}
