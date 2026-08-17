import FeatureFlag
import XCTest

@testable import FeatureFlagUI

/// Editing is the one place a person types free text at a typed system, so parsing has
/// to be exact and refuse anything it cannot represent.
final class FlagEditorValueTests: XCTestCase {

    // MARK: - Rendering

    func testEveryTypeRendersAsText() {
        XCTAssertEqual(FlagValueBox.bool(true).displayString, "true")
        XCTAssertEqual(FlagValueBox.bool(false).displayString, "false")
        XCTAssertEqual(FlagValueBox.int(-7).displayString, "-7")
        XCTAssertEqual(FlagValueBox.double(3.5).displayString, "3.5")
        XCTAssertEqual(FlagValueBox.float(2.5).displayString, "2.5")
        XCTAssertEqual(FlagValueBox.string("hi").displayString, "hi")
        XCTAssertEqual(FlagValueBox.data(Data([0x01, 0x02])).displayString, "AQI=")
        XCTAssertEqual(
            FlagValueBox.date(Date(timeIntervalSince1970: 0)).displayString,
            "1970-01-01T00:00:00Z"
        )
    }

    func testCollectionsRenderAsJSON() {
        XCTAssertEqual(FlagValueBox.array([]).displayString, "[]")
        XCTAssertEqual(FlagValueBox.dictionary([:]).displayString, "{}")
        XCTAssertEqual(
            FlagValueBox.dictionary(["b": .int(2), "a": .int(1)]).displayString,
            #"{"a":1,"b":2}"#
        )
    }

    func testURLsRenderWithoutEscapingTheirSlashes() {
        XCTAssertEqual(
            FlagValueBox.url(URL(string: "https://a.example/x?y=z")!).displayString,
            "https://a.example/x?y=z"
        )
    }

    // MARK: - Parsing

    func testBooleansAcceptTheUsualSpellings() {
        for text in ["true", "TRUE", "yes", "1"] {
            XCTAssertEqual(FlagValueBox(displayString: text, as: .bool), .bool(true), text)
        }
        for text in ["false", "FALSE", "no", "0"] {
            XCTAssertEqual(FlagValueBox(displayString: text, as: .bool), .bool(false), text)
        }
        XCTAssertNil(FlagValueBox(displayString: "maybe", as: .bool))
    }

    func testNumbersRejectAnythingThatIsNotOne() {
        XCTAssertEqual(FlagValueBox(displayString: "-7", as: .int), .int(-7))
        XCTAssertNil(FlagValueBox(displayString: "3.5", as: .int))
        XCTAssertNil(FlagValueBox(displayString: " 3", as: .int))
        XCTAssertNil(FlagValueBox(displayString: "3abc", as: .int))
        XCTAssertEqual(FlagValueBox(displayString: "2.5", as: .float), .float(2.5))
    }

    func testStringsAcceptAnything() {
        XCTAssertEqual(FlagValueBox(displayString: "", as: .string), .string(""))
        XCTAssertEqual(FlagValueBox(displayString: "{not json}", as: .string), .string("{not json}"))
    }

    func testDatesAndDataAndURLsRoundTripThroughText() {
        let cases: [(FlagValueBox, FlagValueType)] = [
            (.date(Date(timeIntervalSince1970: 1_000)), .date),
            (.data(Data([0x01, 0xFF])), .data),
            (.url(URL(string: "https://a.example/x")!), .url),
        ]
        for (box, type) in cases {
            XCTAssertEqual(FlagValueBox(displayString: box.displayString, as: type), box)
        }
    }

    func testMalformedStructuredTextIsRejected() {
        XCTAssertNil(FlagValueBox(displayString: "yesterday", as: .date))
        XCTAssertNil(FlagValueBox(displayString: "!!!", as: .data))
        XCTAssertNil(FlagValueBox(displayString: "{}", as: .array(.string)))
        XCTAssertNil(FlagValueBox(displayString: "[1]", as: .array(.string)))
        XCTAssertNil(FlagValueBox(displayString: "[", as: .array(.string)))
    }

    func testCollectionsRoundTripThroughText() {
        let cases: [(FlagValueBox, FlagValueType)] = [
            (.array([.string("a"), .string("b")]), .array(.string)),
            (.array([]), .array(.int)),
            (.dictionary(["a": .int(1)]), .dictionary(.int)),
            (.dictionary([:]), .dictionary(.bool)),
            (.array([.array([.int(1)])]), .array(.array(.int))),
        ]
        for (box, type) in cases {
            XCTAssertEqual(
                FlagValueBox(displayString: box.displayString, as: type), box, "failed for \(type)"
            )
        }
    }

    // MARK: - Editor selection

    func testDataGetsItsOwnEditor() {
        XCTAssertEqual(entry(valueType: .data).editorKind, .data)
    }

    func testFloatAndDoubleShareTheDecimalEditor() {
        XCTAssertEqual(entry(valueType: .float).editorKind, .decimal)
        XCTAssertEqual(entry(valueType: .double).editorKind, .decimal)
    }

    /// An array of scalars is a list of controls, one per element. A dictionary has no
    /// order to lay out and an array of arrays has no row that reads well, so those two
    /// keep the JSON block.
    func testAnArrayOfScalarsGetsARowPerElement() {
        XCTAssertEqual(entry(valueType: .array(.int)).editorKind, .list(element: .int))
        XCTAssertEqual(entry(valueType: .array(.date)).editorKind, .list(element: .date))
    }

    func testStructuralCollectionsKeepTheJSONEditor() {
        XCTAssertEqual(entry(valueType: .dictionary(.string)).editorKind, .json)
        XCTAssertEqual(entry(valueType: .array(.array(.string))).editorKind, .json)
        XCTAssertEqual(entry(valueType: .array(.dictionary(.int))).editorKind, .json)
    }

    func testCasesWinOverTheUnderlyingType() {
        // An Int-backed enum should still get a picker, not a number field.
        let entry = entry(valueType: .int, cases: [.int(1), .int(2)])
        XCTAssertEqual(entry.editorKind, .picker([.int(1), .int(2)]))
    }

    func testAnEmptyCaseListFallsBackToTheTypesEditor() {
        XCTAssertEqual(entry(valueType: .string, cases: []).editorKind, .text)
    }

    private func entry(valueType: FlagValueType, cases: [FlagValueBox]? = nil) -> FlagSchema.Entry {
        FlagSchema.Entry(
            key: "a",
            propertyPath: ["a"],
            description: "",
            valueType: valueType,
            defaultValue: .string(""),
            cases: cases,
            remoteKey: nil
        )
    }
}

extension FlagEditorValueTests {

    /// Data is base64: long, opaque, and impossible to verify a fragment of. It belongs
    /// in the wrapping block, which shows the whole value and carries a copy button.
    func testDataIsEditedAsABlockRatherThanASingleLine() {
        let data = FlagSchema.Entry(
            key: "blob",
            propertyPath: ["blob"],
            description: "",
            valueType: .data,
            defaultValue: .data(Data())
        )
        XCTAssertEqual(data.editorKind, .data)
        XCTAssertTrue(data.editorKind.wantsWrappingEditor)
    }

    func testStructuralCollectionsAlsoUseTheWrappingEditor() {
        for type in [FlagValueType.dictionary(.int), .array(.array(.string))] {
            let entry = FlagSchema.Entry(
                key: "k", propertyPath: ["k"], description: "",
                valueType: type, defaultValue: .array([])
            )
            XCTAssertTrue(entry.editorKind.wantsWrappingEditor, "\(type)")
        }
    }

    /// A list pushes to its own screen, so it never needs the wrapping block.
    func testAListDoesNotUseTheWrappingEditor() {
        let entry = FlagSchema.Entry(
            key: "k", propertyPath: ["k"], description: "",
            valueType: .array(.string), defaultValue: .array([])
        )
        XCTAssertFalse(entry.editorKind.wantsWrappingEditor)
    }

    func testScalarsStayOnASingleLine() {
        let scalars: [(FlagValueType, FlagValueBox)] = [
            (.string, .string("")), (.int, .int(0)), (.double, .double(0)),
            (.float, .float(0)), (.url, .url(URL(string: "https://a.example")!)),
            (.date, .date(Date())), (.bool, .bool(false)),
        ]
        for (type, value) in scalars {
            let entry = FlagSchema.Entry(
                key: "k", propertyPath: ["k"], description: "",
                valueType: type, defaultValue: value
            )
            XCTAssertFalse(entry.editorKind.wantsWrappingEditor, "\(type) should stay inline")
        }
    }

    func testAPickerIsNeverAWrappingEditor() {
        let entry = FlagSchema.Entry(
            key: "tier", propertyPath: ["tier"], description: "",
            valueType: .string, defaultValue: .string("free"),
            cases: [.string("free"), .string("pro")]
        )
        XCTAssertFalse(entry.editorKind.wantsWrappingEditor)
    }
}
