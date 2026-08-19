import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import FeatureFlagMacros

private let recordMacros: [String: Macro.Type] = [
    "FlagRecord": FlagRecordMacro.self
]

/// `@FlagRecord` writes the boxing a record would otherwise need by hand: a shape for
/// the companion, a box per field, and the way back.
final class FlagRecordMacroTests: XCTestCase {

    func testExpandsToAShapeABoxAndTheWayBack() {
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var name: String
                var enabled: Bool
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var name: String
                    var enabled: Bool

                    static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                        [
                            FeatureFlag.FlagRecordField(
                                name: "name",
                                type: String.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: String.self),
                                defaultValue: nil,
                                fields: FeatureFlag._flagRecordShape(of: String.self)
                            ),
                            FeatureFlag.FlagRecordField(
                                name: "enabled",
                                type: Bool.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: Bool.self),
                                defaultValue: nil,
                                fields: FeatureFlag._flagRecordShape(of: Bool.self)
                            )
                        ]
                    }

                    var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                        [
                            "name": name.box,
                            "enabled": enabled.box
                        ]
                    }
                }

                extension Endpoint {
                    init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
                        guard let name = flagRecordBoxes["name"].flatMap(String.init(box:)),
                              let enabled = flagRecordBoxes["enabled"].flatMap(Bool.init(box:)) else {
                            return nil
                        }
                        self.name = name
                        self.enabled = enabled
                    }
                }

                @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'")
                extension Endpoint: FeatureFlag.FlagValue {
                    static var flagValueType: FeatureFlag.FlagValueType {
                        fatalError("unavailable")
                    }
                    init?(box: FeatureFlag.FlagValueBox) {
                        fatalError("unavailable")
                    }
                    var box: FeatureFlag.FlagValueBox {
                        fatalError("unavailable")
                    }
                }
                """,
            macros: recordMacros
        )
    }

    func testGeneratedMembersMatchAPublicRecordsAccessLevel() {
        // FlagRecord is a public protocol, so internal members cannot satisfy it.
        assertMacroExpansion(
            """
            @FlagRecord
            public struct Endpoint {
                public var name: String
            }
            """,
            expandedSource: """
                public struct Endpoint {
                    public var name: String

                    public static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                        [
                            FeatureFlag.FlagRecordField(
                                name: "name",
                                type: String.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: String.self),
                                defaultValue: nil,
                                fields: FeatureFlag._flagRecordShape(of: String.self)
                            )
                        ]
                    }

                    public var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                        [
                            "name": name.box
                        ]
                    }
                }

                extension Endpoint {
                    public init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
                        guard let name = flagRecordBoxes["name"].flatMap(String.init(box:)) else {
                            return nil
                        }
                        self.name = name
                    }
                }

                @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'")
                extension Endpoint: FeatureFlag.FlagValue {
                    public static var flagValueType: FeatureFlag.FlagValueType {
                        fatalError("unavailable")
                    }
                    public init?(box: FeatureFlag.FlagValueBox) {
                        fatalError("unavailable")
                    }
                    public var box: FeatureFlag.FlagValueBox {
                        fatalError("unavailable")
                    }
                }
                """,
            macros: recordMacros
        )
    }

    func testAFieldWrittenWithAValueCarriesItAsItsDefault() {
        // Cast the way `@Flag` casts a default, so the expression compiles given the
        // annotation the field has to carry anyway.
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var weight: Int = 1
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var weight: Int = 1

                    static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                        [
                            FeatureFlag.FlagRecordField(
                                name: "weight",
                                type: Int.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: Int.self),
                                defaultValue: (1 as Int).box,
                                fields: FeatureFlag._flagRecordShape(of: Int.self)
                            )
                        ]
                    }

                    var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                        [
                            "weight": weight.box
                        ]
                    }
                }

                extension Endpoint {
                    init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
                        guard let weight = flagRecordBoxes["weight"].flatMap(Int.init(box:)) else {
                            return nil
                        }
                        self.weight = weight
                    }
                }

                @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'")
                extension Endpoint: FeatureFlag.FlagValue {
                    static var flagValueType: FeatureFlag.FlagValueType {
                        fatalError("unavailable")
                    }
                    init?(box: FeatureFlag.FlagValueBox) {
                        fatalError("unavailable")
                    }
                    var box: FeatureFlag.FlagValueBox {
                        fatalError("unavailable")
                    }
                }
                """,
            macros: recordMacros
        )
    }

    // MARK: - What is and is not a field

    func testConstantsAreFieldsToo() {
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                let name: String
            }
            """,
            expandedSource: """
                struct Endpoint {
                    let name: String

                    static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                        [
                            FeatureFlag.FlagRecordField(
                                name: "name",
                                type: String.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: String.self),
                                defaultValue: nil,
                                fields: FeatureFlag._flagRecordShape(of: String.self)
                            )
                        ]
                    }

                    var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                        [
                            "name": name.box
                        ]
                    }
                }

                extension Endpoint {
                    init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
                        guard let name = flagRecordBoxes["name"].flatMap(String.init(box:)) else {
                            return nil
                        }
                        self.name = name
                    }
                }

                @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'")
                extension Endpoint: FeatureFlag.FlagValue {
                    static var flagValueType: FeatureFlag.FlagValueType {
                        fatalError("unavailable")
                    }
                    init?(box: FeatureFlag.FlagValueBox) {
                        fatalError("unavailable")
                    }
                    var box: FeatureFlag.FlagValueBox {
                        fatalError("unavailable")
                    }
                }
                """,
            macros: recordMacros
        )
    }

    func testComputedAndStaticPropertiesAreNotFields() {
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var name: String
                static let fallback = "none"
                var shouted: String { name.uppercased() }
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var name: String
                    static let fallback = "none"
                    var shouted: String { name.uppercased() }

                    static var flagRecordShape: [FeatureFlag.FlagRecordField] {
                        [
                            FeatureFlag.FlagRecordField(
                                name: "name",
                                type: String.flagValueType,
                                cases: FeatureFlag._flagValueCases(of: String.self),
                                defaultValue: nil,
                                fields: FeatureFlag._flagRecordShape(of: String.self)
                            )
                        ]
                    }

                    var flagRecordBoxes: [String: FeatureFlag.FlagValueBox] {
                        [
                            "name": name.box
                        ]
                    }
                }

                extension Endpoint {
                    init?(flagRecordBoxes: [String: FeatureFlag.FlagValueBox]) {
                        guard let name = flagRecordBoxes["name"].flatMap(String.init(box:)) else {
                            return nil
                        }
                        self.name = name
                    }
                }

                @available(*, unavailable, message: "a record is stored as a list — declare the flag as 'FlagRecords<Endpoint>' rather than 'Endpoint' or '[Endpoint]'")
                extension Endpoint: FeatureFlag.FlagValue {
                    static var flagValueType: FeatureFlag.FlagValueType {
                        fatalError("unavailable")
                    }
                    init?(box: FeatureFlag.FlagValueBox) {
                        fatalError("unavailable")
                    }
                    var box: FeatureFlag.FlagValueBox {
                        fatalError("unavailable")
                    }
                }
                """,
            macros: recordMacros
        )
    }

    // MARK: - Diagnostics

    func testNonStructIsRejectedWithoutAddingAConformance() {
        assertMacroExpansion(
            """
            @FlagRecord
            class Endpoint {
            }
            """,
            expandedSource: """
                class Endpoint {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@FlagRecord' can only be applied to a struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: recordMacros
        )
    }

    func testARecordWithNoFieldsIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
            }
            """,
            expandedSource: """
                struct Endpoint {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        '@FlagRecord' needs at least one stored property: a record is a \
                        shape, and an empty one gives the editor nothing to show
                        """,
                    line: 1,
                    column: 1
                )
            ],
            macros: recordMacros
        )
    }

    func testAFieldWithoutATypeAnnotationIsDiagnosed() {
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var name = "prod"
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var name = "prod"
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        record fields need an explicit type annotation, for example \
                        'var name: String'
                        """,
                    line: 3,
                    column: 5
                ),
                DiagnosticSpec(
                    message: """
                        '@FlagRecord' needs at least one stored property: a record is a \
                        shape, and an empty one gives the editor nothing to show
                        """,
                    line: 1,
                    column: 1
                ),
            ],
            macros: recordMacros
        )
    }

    func testFieldsDeclaredTogetherAreDiagnosed() {
        // Only the first of a shared declaration would be generated for, and dropping
        // the rest silently leaves the initialiser incomplete — which surfaces as
        // "return from initializer without initializing all stored properties" pointed
        // into generated code the author never wrote.
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var host: String, port: String
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var host: String, port: String
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        declare one field per line: '@FlagRecord' generates a shape entry \
                        and a box for each one by name, and only the first of a shared \
                        declaration would be written
                        """,
                    line: 3,
                    column: 5
                ),
                DiagnosticSpec(
                    message: """
                        '@FlagRecord' needs at least one stored property: a record is a \
                        shape, and an empty one gives the editor nothing to show
                        """,
                    line: 1,
                    column: 1
                ),
            ],
            macros: recordMacros
        )
    }

    func testAnOptionalFieldIsDiagnosed() {
        // The same reasoning as flags: a record is rebuilt from stored text, and an
        // absent field is indistinguishable from one that was never written.
        assertMacroExpansion(
            """
            @FlagRecord
            struct Endpoint {
                var name: String?
            }
            """,
            expandedSource: """
                struct Endpoint {
                    var name: String?
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        record fields cannot be optional: a field is either part of the \
                        shape or it is not. Use a sentinel the type already has, or an \
                        enum with a case for 'unset'
                        """,
                    line: 3,
                    column: 5
                ),
                DiagnosticSpec(
                    message: """
                        '@FlagRecord' needs at least one stored property: a record is a \
                        shape, and an empty one gives the editor nothing to show
                        """,
                    line: 1,
                    column: 1
                ),
            ],
            macros: recordMacros
        )
    }
}
