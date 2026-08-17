import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import FeatureFlagMacros

private let testMacros: [String: Macro.Type] = [
    "FlagContainer": FlagContainerMacro.self,
    "FlagGroup": FlagGroupMacro.self,
]

/// Misuse should be explained at the point of the mistake. Without these, a missing
/// type annotation surfaces as a wall of errors inside generated code.
final class FlagContainerDiagnosticTests: XCTestCase {

    func testNonStructIsRejectedWithoutAddingAConformance() {
        assertMacroExpansion(
            """
            @FlagContainer
            class AppFlags {
            }
            """,
            expandedSource: """
                class AppFlags {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@FlagContainer' can only be applied to a struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testGeneratedMembersMatchAPublicContainersAccessLevel() {
        // FlagContainer is a public protocol, so internal members cannot satisfy it.
        // Any framework exposing its flags publicly hits this on the first build.
        assertMacroExpansion(
            """
            @FlagContainer
            public struct AppFlags {
                @Flag(default: false, description: "New onboarding")
                public var newOnboarding: Bool
            }
            """,
            expandedSource: """
                public struct AppFlags {
                    @Flag(default: false, description: "New onboarding")
                    public var newOnboarding: Bool

                    public init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {
                        _newOnboarding = FeatureFlag.Flag(
                            default: false,
                            description: "New onboarding",
                            lookup: _lookup,
                            keyPath: _keyPrefix.appending("newOnboarding")
                        )
                    }

                    public static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [
                            .flag(
                                FeatureFlag.FlagDescriptor(
                                    propertyName: "newOnboarding",
                                    keyPath: FeatureFlag.FlagKeyPath(["newOnboarding"]),
                                    description: "New onboarding",
                                    valueType: Bool.flagValueType,
                                    defaultValue: (false as Bool).box,
                                    cases: FeatureFlag._flagValueCases(of: Bool.self),
                                    remoteKey: nil,
                                    recordShape: FeatureFlag._flagRecordShape(of: Bool.self)
                                )
                            )
                        ]
                    }
                }
                """,
            macros: testMacros
        )
    }

    func testFlagWithoutATypeAnnotationIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: false, description: "New onboarding")
                var newOnboarding
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: false, description: "New onboarding")
                    var newOnboarding

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "flags need an explicit type annotation, for example 'var newOnboarding: Bool'",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    func testFlagWithAnInitialValueIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: false, description: "New onboarding")
                var newOnboarding: Bool = false
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: false, description: "New onboarding")
                    var newOnboarding: Bool = false

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "flags must be simple stored properties, without an initial value or accessors",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    func testFlagWithoutADefaultIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(description: "New onboarding")
                var newOnboarding: Bool
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(description: "New onboarding")
                    var newOnboarding: Bool

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@Flag' needs a 'default' value to fall back to",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    func testFlagWithoutADescriptionIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: false)
                var newOnboarding: Bool
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: false)
                    var newOnboarding: Bool

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "flags need a 'description' so the companion app can explain them",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }
}

// MARK: - Optionals

extension FlagContainerDiagnosticTests {

    /// Without this, an optional flag fails as "generic struct 'Flag' requires that
    /// 'String?' conform to 'FlagValue'", followed by an inferred-generic error pointing
    /// into expanded code the author never wrote. True, and no help at all about what to
    /// do instead.
    func testAnOptionalFlagIsRejectedWithAnExplanation() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: nil, description: "Endpoint")
                var endpoint: String?
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: nil, description: "Endpoint")
                    var endpoint: String?

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "flags cannot be optional: a flag always has a value, because "
                        + "'default' is what it falls back to. Use a sentinel the type "
                        + "already has, or an enum with a case for 'unset'",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    /// `Optional<String>` spelled the long way is the same declaration.
    func testTheLongSpellingIsRejectedToo() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: nil, description: "Endpoint")
                var endpoint: Optional<String>
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: nil, description: "Endpoint")
                    var endpoint: Optional<String>

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "flags cannot be optional: a flag always has a value, because "
                        + "'default' is what it falls back to. Use a sentinel the type "
                        + "already has, or an enum with a case for 'unset'",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    /// And so is an implicitly unwrapped one, which is still an Optional underneath.
    func testAnImplicitlyUnwrappedOptionalIsRejected() {
        assertMacroExpansion(
            """
            @FlagContainer
            struct AppFlags {
                @Flag(default: nil, description: "Endpoint")
                var endpoint: String!
            }
            """,
            expandedSource: """
                struct AppFlags {
                    @Flag(default: nil, description: "Endpoint")
                    var endpoint: String!

                    init(_lookup: any FeatureFlag.FlagLookup, _keyPrefix: FeatureFlag.FlagKeyPath) {

                    }

                    static var flagDescriptors: [FeatureFlag.FlagSchemaNode] {
                        [

                        ]
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "flags cannot be optional: a flag always has a value, because "
                        + "'default' is what it falls back to. Use a sentinel the type "
                        + "already has, or an enum with a case for 'unset'",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }
}
