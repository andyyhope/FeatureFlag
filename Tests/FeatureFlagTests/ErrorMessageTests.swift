import XCTest

@testable import FeatureFlag

/// What a developer actually reads when something goes wrong.
///
/// Every one of these used to print as a reflected enum — module prefixes, struct
/// syntax, and the category of the problem but never the value that caused it. Worse,
/// `localizedDescription` said "The operation couldn't be completed", which is what
/// most apps log.
final class ErrorMessageTests: XCTestCase {

    /// Both spellings have to be good: `\(error)` is what you print, and
    /// `localizedDescription` is what a logger and an alert reach for.
    private func messages(_ error: some Error) -> [String] {
        [String(describing: error), error.localizedDescription]
    }

    private func assertSays(
        _ error: some Error,
        _ fragments: String...,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for message in messages(error) {
            for fragment in fragments {
                XCTAssertTrue(
                    message.contains(fragment),
                    "expected \"\(fragment)\" in: \(message)",
                    file: file,
                    line: line
                )
            }
            XCTAssertFalse(
                message.contains("FeatureFlag."),
                "a reflected type name leaked into: \(message)",
                file: file,
                line: line
            )
            XCTAssertFalse(
                message.contains("couldn’t be completed"),
                "the system placeholder leaked into: \(message)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Remote overrides

    func testARejectedRemotePayloadNamesTheValueAndWhatWasExpected() {
        let error = RemoteOverrideError.rejected([
            RemoteOverrideProblem(
                key: "new-onboarding",
                remoteKey: "featureToggles.onboarding",
                kind: .typeMismatch,
                expected: "bool",
                found: "\"yes\""
            )
        ])

        assertSays(
            error,
            "featureToggles.onboarding",
            "new-onboarding",
            "bool",
            "\"yes\"",
            "Nothing was applied"
        )
    }

    func testARejectedPayloadSaysHowManyProblemsThereWere() {
        let error = RemoteOverrideError.rejected([
            RemoteOverrideProblem(key: "a", remoteKey: "x.a", kind: .typeMismatch),
            RemoteOverrideProblem(key: "b", remoteKey: "x.b", kind: .typeMismatch),
        ])

        assertSays(error, "2 problems")
    }

    func testAnUnknownCaseListsTheOnesThatWouldHaveWorked() {
        let error = RemoteOverrideError.rejected([
            RemoteOverrideProblem(
                key: "tier",
                remoteKey: "config.tier",
                kind: .unknownCase,
                expected: "free, pro",
                found: "\"gold\""
            )
        ])

        assertSays(error, "\"gold\"", "free, pro")
    }

    func testAnUnknownKeyPointsAtTheMapperRatherThanTheBackend() {
        // DotPathMapper cannot produce this — it only emits keys it read from the
        // schema — so reaching it means a custom mapper returned a key that does not
        // exist, and saying "check your payload" would send people the wrong way.
        let error = RemoteOverrideError.rejected([
            RemoteOverrideProblem(key: "new-onbaording", remoteKey: "new-onbaording", kind: .unknownKey)
        ])

        assertSays(error, "new-onbaording", "mapper")
    }

    func testAMalformedPayloadSaysWhatWasWrongWithIt() {
        assertSays(RemoteOverrideError.malformed("not valid JSON"), "not valid JSON")
    }

    // MARK: - Import

    func testARejectedImportNamesTheFlagAndTheProblem() {
        let error = FlagImportError.rejected([
            FlagImportProblem(key: "page-size", kind: .typeMismatch, expected: "int", found: "\"big\"")
        ])

        assertSays(error, "page-size", "int", "\"big\"", "Nothing was applied")
    }

    func testAnUnsupportedDocumentVersionSaysWhichBuildIsBehind() {
        assertSays(FlagImportError.unsupportedFormatVersion(9), "9", "1")
    }

    // MARK: - Schema

    func testAnUnpublishedSchemaSaysWhatToGoAndDo() {
        // The most common first-run failure, and the one people misdiagnose as a broken
        // App Group when the host has simply never been run.
        assertSays(FlagSchemaError.notPublished, "publishSchema", "App Group")
    }

    func testAMalformedSchemaSaysWhatWasWrongWithIt() {
        assertSays(FlagSchemaError.malformed("missing formatVersion"), "missing formatVersion")
    }

    // MARK: - QR codes

    func testAnOversizedCodeSaysHowFarOverItIs() {
        assertSays(
            FlagQRCodeError.payloadTooLarge(bytes: 3400, limit: 2900, overrideCount: 12),
            "12", "3400", "2900"
        )
    }

    func testAnUnrecognisedCodeSaysWhatAFlagCodeLooksLike() {
        assertSays(FlagQRCodeError.unrecognisedFormat, "FFQR1:")
    }

    func testACorruptCodeBlamesThePartialScanItUsuallyIs() {
        assertSays(FlagQRCodeError.corrupt, "scan")
    }

    // MARK: - Signals

    func testAnUnacknowledgedSignalDoesNotClaimTheHostIsClosed() {
        // It might be running and slow. Saying "the app is not running" as fact is a
        // lie the caller then shows someone.
        assertSays(FlagSignalError.notAcknowledged, "did not confirm")
    }

    func testAnUnavailableAppGroupNamesTheGroupAndTheEntitlement() {
        assertSays(
            FlagSignalError.unavailableAppGroup("group.example.flags"),
            "group.example.flags", "entitlement"
        )
    }

    // MARK: - The messages the real paths actually produce

    func testARealRemoteRejectionNamesThePathTheValueAndTheType() {
        let remote = RemoteOverrideSource(MessageFlags.self)

        XCTAssertThrowsError(
            try remote.apply(
                Data(#"{"featureToggles":{"onboarding":"yes"}}"#.utf8), format: .json
            )
        ) { error in
            assertSays(
                error,
                "featureToggles.onboarding",
                "new-onboarding",
                "expected bool",
                "\"yes\"",
                "Nothing was applied"
            )
        }
    }

    func testARealUnknownCaseListsTheCasesThisBuildHas() {
        let remote = RemoteOverrideSource(MessageFlags.self)

        XCTAssertThrowsError(
            try remote.apply(Data(#"{"config":{"tier":"gold"}}"#.utf8), format: .json)
        ) { error in
            assertSays(error, "checkout-tier", "\"gold\"", "free, pro")
        }
    }

    func testARealImportRejectionNamesTheFlagTheValueAndTheType() {
        let pole = FlagPole(MessageFlags.self, sources: [SnapshotSource(name: "l")])
        let document = #"{"formatVersion":1,"values":{"page-size":"big"}}"#

        XCTAssertThrowsError(try pole.importPayload(Data(document.utf8), as: .json)) { error in
            assertSays(error, "page-size", "expected int", "\"big\"")
        }
    }

    func testARealRecordRejectionSaysWhichFieldsWereExpected() {
        let pole = FlagPole(MessageFlags.self, sources: [SnapshotSource(name: "l")])
        let document = #"{"formatVersion":1,"values":{"endpoints":"nonsense"}}"#

        XCTAssertThrowsError(try pole.importPayload(Data(document.utf8), as: .json)) { error in
            assertSays(error, "endpoints", "a list of records", "name, port", "\"nonsense\"")
        }
    }

    // MARK: - Sources and serialisation

    func testWritingWithNothingWritableSaysWhatToAdd() {
        assertSays(FlagError.noMutableSource, "UserDefaultsSource")
    }

    func testARefusedValueNamesTheFlag() {
        assertSays(FlagError.unsupportedValue("page-size"), "page-size")
    }

    func testANonFiniteNumberNamesTheFlagAndWhyJSONCannotTakeIt() {
        assertSays(FlagSerializationError.nonFiniteNumber("ratio"), "ratio", "JSON")
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro
}

@FlagRecord
private struct Endpoint {
    var name: String
    var port: Int
}

@FlagContainer
private struct MessageFlags {

    @Flag(default: false, description: "Onboarding", remoteKey: "featureToggles.onboarding")
    var newOnboarding: Bool

    @Flag(default: 10, description: "Page size", remoteKey: "config.pageSize")
    var pageSize: Int

    @Flag(default: Tier.free, description: "Tier", remoteKey: "config.tier")
    var checkoutTier: Tier

    @Flag(default: [], description: "Endpoints", remoteKey: "config.endpoints")
    var endpoints: FlagRecords<Endpoint>
}
