import XCTest

@testable import FeatureFlag

/// A container can say what its flags are for, and the companion shows it.
///
/// The app name answers "whose flags are these"; this answers "what are they", which
/// is the question someone handed an unfamiliar debug build actually has.
final class FlagContainerDescriptionTests: XCTestCase {

    func testAContainerPublishesItsDescription() {
        XCTAssertEqual(
            DescribedFlags.flagContainerDescription,
            "Everything the checkout team can turn on"
        )
    }

    func testAContainerWithoutOneSaysNothing() {
        XCTAssertNil(PlainFlags.flagContainerDescription)
    }

    func testTheSchemaCarriesIt() {
        XCTAssertEqual(
            FlagSchema(DescribedFlags.self).description,
            "Everything the checkout team can turn on"
        )
    }

    func testTheDescriptionSurvivesTheDocumentTheCompanionReads() throws {
        let schema = FlagSchema(DescribedFlags.self)

        let reread = try FlagSchema(jsonData: schema.jsonData())

        XCTAssertEqual(reread.description, "Everything the checkout team can turn on")
    }

    func testASchemaWithoutOneStillDecodes() throws {
        let reread = try FlagSchema(jsonData: FlagSchema(PlainFlags.self).jsonData())

        XCTAssertNil(reread.description)
    }

    func testADocumentFromBeforeDescriptionsExistedStillDecodes() throws {
        let json = """
            {
              "formatVersion": 1,
              "generatedAt": "2026-01-01T00:00:00.000Z",
              "flags": [
                { "key": "one", "propertyPath": ["one"], "description": "One",
                  "valueType": "bool", "defaultValue": false }
              ],
              "groups": []
            }
            """

        let schema = try FlagSchema(jsonData: Data(json.utf8))

        XCTAssertNil(schema.description)
        XCTAssertEqual(schema.flags.count, 1)
    }

    func testADescriptionDoesNotDisturbTheFlagsBesideIt() {
        let schema = FlagSchema(DescribedFlags.self)

        XCTAssertEqual(schema.flags.map(\.key), ["new-onboarding"])
    }
}

// MARK: - Fixtures

@FlagContainer(description: "Everything the checkout team can turn on")
private struct DescribedFlags {

    @Flag(default: false, description: "Onboarding")
    var newOnboarding: Bool
}

@FlagContainer
private struct PlainFlags {

    @Flag(default: false, description: "Onboarding")
    var newOnboarding: Bool
}
