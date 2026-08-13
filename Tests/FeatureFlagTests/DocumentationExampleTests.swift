import Combine
import XCTest

@testable import FeatureFlag

/// Every code sample in the FeatureFlag DocC catalog, compiled and run.
///
/// Documentation that has drifted from the API is worse than none, and nothing else in
/// the suite would notice. The samples live in `Sources/FeatureFlag/FeatureFlag.docc`;
/// change one there and change it here.
final class DocumentationExampleTests: XCTestCase {

    // MARK: - FeatureFlag.md

    /// The landing page's declaration and read.
    func testLandingPageSampleReads() throws {
        let local = SnapshotSource(name: "local")
        let flags = FlagPole(DocsAppFlags.self, sources: [local])

        XCTAssertFalse(flags.newOnboarding)

        try local.setBox(.bool(true), for: "new-onboarding")
        XCTAssertTrue(flags.newOnboarding)
    }

    // MARK: - GettingStarted.md

    /// Step three: with nothing stored anywhere, every flag reports its default.
    func testAPoleWithNoOverridesReportsCompiledDefaults() {
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])

        XCTAssertFalse(flags.newOnboarding)
        XCTAssertEqual(flags.pageSize, 20)
        XCTAssertFalse(flags.checkout.applePay)
    }

    /// Step four, minus the App Group: publishing writes a document a companion can read
    /// back without linking any of this.
    func testPublishingWritesASchemaACompanionCanRead() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let flags = FlagPole(DocsAppFlags.self, sources: [])
        try flags.publishSchema(inDirectory: directory)

        let loaded = try FlagSchema(contentsOfDirectory: directory)
        XCTAssertEqual(
            loaded.flags.map(\.key),
            ["new-onboarding", "page-size", "checkout.apple-pay", "checkout.express.one-tap"]
        )
        XCTAssertEqual(loaded.groups.map(\.description), ["Checkout", "Express"])
    }

    // MARK: - DeclaringFlags.md

    /// The documented key for a two-level nesting.
    func testNestingProducesTheDocumentedKey() {
        let flags = FlagPole(DocsAppFlags.self, sources: [])
        XCTAssertEqual(flags.flags.checkout.express.$oneTap.key, "checkout.express.one-tap")
    }

    /// The key encoding table, exactly as tabulated.
    func testTheKeyEncodingTableIsAccurate() {
        func key(_ encoding: KeyEncoding) -> FlagKey {
            FlagPole(DocsAppFlags.self, sources: [], keyEncoding: encoding)
                .flags.checkout.express.$oneTap.key
        }

        XCTAssertEqual(key(.kebabcase), "checkout.express.one-tap")
        XCTAssertEqual(key(.snakecase), "checkout.express.one_tap")
        XCTAssertEqual(key(.verbatim), "checkout.express.oneTap")
    }

    /// The claim about acronyms and digits.
    func testWordSplittingHandlesAcronymsAndDigits() {
        let flags = FlagPole(DocsAwkwardNameFlags.self, sources: [])
        XCTAssertEqual(flags.flags.$useHTTPSOnly.key, "use-https-only")
        XCTAssertEqual(flags.flags.$checkoutV2.key, "checkout-v2")
    }

    /// The custom encoding sample.
    func testTheCustomKeyEncodingSampleCompilesAndApplies() {
        let screaming = KeyEncoding(separator: "__") { $0.uppercased() }
        let flags = FlagPole(DocsAppFlags.self, sources: [], keyEncoding: screaming)

        XCTAssertEqual(flags.flags.checkout.express.$oneTap.key, "CHECKOUT__EXPRESS__ONETAP")
    }

    /// Everything the article says a projected value carries.
    func testAnAccessorCarriesTheDocumentedMetadata() {
        let flag = FlagPole(DocsAppFlags.self, sources: []).flags.$newOnboarding

        XCTAssertEqual(flag.key, "new-onboarding")
        XCTAssertEqual(flag.description, "Show the redesigned onboarding")
        XCTAssertEqual(flag.defaultValue, false)
        XCTAssertEqual(flag.remoteKey, "featureToggles.onboarding.v2")
        XCTAssertFalse(flag.currentValue)
        XCTAssertTrue(type(of: flag.publisher) == AnyPublisher<Bool, Never>.self)
    }

    /// The detached-flag sample: no pole, no setup, still readable.
    func testADetachedFlagReportsItsDefault() {
        XCTAssertTrue(OnboardingPreviewFlags().newOnboarding)
    }

    /// The public-container sample compiles, which is the only claim being made.
    func testAPublicContainerResolves() {
        XCTAssertFalse(FlagPole(DocsPublicFlags.self, sources: []).newOnboarding)
    }

    // MARK: - FlagValues.md

    /// Every built-in type in the inventory, declared and read.
    func testTheBuiltInTypeInventoryCompilesAndReads() {
        let flags = FlagPole(DocsEveryTypeFlags.self, sources: [])

        XCTAssertFalse(flags.enabled)
        XCTAssertEqual(flags.pageSize, 20)
        XCTAssertEqual(flags.rolloutShare, 0.5)
        XCTAssertEqual(flags.scale, 1.0)
        XCTAssertEqual(flags.channel, "beta")
        XCTAssertEqual(flags.payload, Data())
        XCTAssertEqual(flags.launchesAt, .distantPast)
        XCTAssertEqual(flags.endpoint, URL(string: "https://example.com")!)
    }

    /// The claim that a URL is stored as its string form rather than an archived blob.
    func testAURLIsStoredAsAString() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsEveryTypeFlags.self, sources: [local])

        try flags.setOverride(URL(string: "https://staging.example.com/v3")!, for: flags.flags.$endpoint)

        XCTAssertEqual(
            local.values["endpoint"]?.propertyListValue as? String,
            "https://staging.example.com/v3"
        )
    }

    /// The collections sample.
    func testCollectionFlagsRoundTrip() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsCollectionFlags.self, sources: [local])

        XCTAssertEqual(flags.markets, [])
        XCTAssertEqual(flags.rolloutByMarket, [:])

        try flags.setOverride(["au", "nz"], for: flags.flags.$markets)
        try flags.setOverride(["au": 0.5], for: flags.flags.$rolloutByMarket)

        XCTAssertEqual(flags.markets, ["au", "nz"])
        XCTAssertEqual(flags.rolloutByMarket, ["au": 0.5])
    }

    /// A raw-value enum conforms with no implementation.
    func testAStringEnumFlagNeedsNoImplementation() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsEnumFlags.self, sources: [local])

        XCTAssertEqual(flags.tier, .free)

        try flags.setOverride(DocsTier.pro, for: flags.flags.$tier)
        XCTAssertEqual(flags.tier, .pro)
    }

    /// The claim that `FlagValueCases` is what puts the cases in the schema — and so
    /// what earns the flag a picker rather than a text field.
    func testFlagValueCasesPublishesTheCases() throws {
        let schema = FlagPole(DocsEnumFlags.self, sources: []).schema

        let tier = try XCTUnwrap(schema.flags.first { $0.key == "tier" })
        XCTAssertEqual(tier.cases, [.string("free"), .string("pro"), .string("enterprise")])

        let retry = try XCTUnwrap(schema.flags.first { $0.key == "retry-policy" })
        XCTAssertEqual(retry.cases, [.int(0), .int(1), .int(3)])
    }

    /// The claim that a case the app cannot represent is rejected rather than ignored.
    func testAnUnknownEnumCaseIsRejected() {
        let remote = RemoteOverrideSource(DocsEnumFlags.self)
        XCTAssertThrowsError(
            try remote.apply(Data(#"{"cfg": {"tier": "platinum"}}"#.utf8), format: .json)
        ) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownCase])
        }
    }

    /// The custom `FlagValue` sample.
    func testTheCustomFlagValueSampleWorks() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsCustomValueFlags.self, sources: [local])

        XCTAssertEqual(flags.rollout.amount, 0)

        try flags.setOverride(Percentage(amount: 0.25), for: flags.flags.$rollout)
        XCTAssertEqual(flags.rollout.amount, 0.25)
        XCTAssertEqual(local.values["rollout"], .double(0.25))
    }

    /// The claim that refusing a box falls back rather than crashing.
    func testARefusedBoxFallsBackToTheDefault() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsCustomValueFlags.self, sources: [local])

        try local.setBox(.string("nonsense"), for: "rollout")
        XCTAssertEqual(flags.rollout.amount, 0, "a stored value it cannot read should fall back")
    }

    /// The box sample at the foot of the article.
    func testTheBoxSample() {
        let box = FlagValueBox.bool(true)
        XCTAssertTrue(box.matches(.bool))
        XCTAssertEqual(Bool(box: box), true)
    }

    // MARK: - SourcesAndPrecedence.md

    /// The stack order is the precedence, and the default is what is left.
    func testTheStackOrderIsThePrecedence() throws {
        let local = SnapshotSource(name: "App Group")
        let remote = SnapshotSource(name: "Remote")
        let flags = FlagPole(DocsAppFlags.self, sources: [local, remote])

        XCTAssertFalse(flags.newOnboarding, "nothing set: the compiled default")

        try remote.setBox(.bool(true), for: "new-onboarding")
        XCTAssertTrue(flags.newOnboarding, "remote supplies it")

        try local.setBox(.bool(false), for: "new-onboarding")
        XCTAssertFalse(flags.newOnboarding, "local is above remote, so local wins")
    }

    /// The SnapshotSource sample.
    func testTheSnapshotSourceSample() throws {
        let local = SnapshotSource(name: "test")
        let flags = FlagPole(DocsAppFlags.self, sources: [local])

        try local.setBox(.bool(true), for: "checkout.apple-pay")
        XCTAssertTrue(flags.checkout.applePay)
    }

    /// Setting and clearing, exactly as written.
    func testTheOverrideSample() throws {
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])

        try flags.setOverride(true, for: flags.flags.$newOnboarding)
        XCTAssertTrue(flags.newOnboarding)

        try flags.removeOverride(for: flags.flags.$newOnboarding)
        XCTAssertFalse(flags.newOnboarding)

        try flags.setOverride(true, for: flags.flags.$newOnboarding)
        try flags.removeAllOverrides()
        XCTAssertTrue(flags.overrides.isEmpty)
    }

    /// The claim that writing with no mutable source throws, rather than doing nothing.
    func testWritingWithNoMutableSourceThrows() {
        let flags = FlagPole(DocsAppFlags.self, sources: [])
        XCTAssertThrowsError(try flags.setOverride(true, for: flags.flags.$newOnboarding)) {
            XCTAssertEqual($0 as? FlagError, .noMutableSource)
        }
    }

    /// The "why is this flag false?" sample.
    func testResolutionNamesTheWinningSource() throws {
        let local = SnapshotSource(name: "App Group")
        let flags = FlagPole(DocsAppFlags.self, sources: [local])

        var resolution = flags.resolution(for: flags.flags.$newOnboarding)
        XCTAssertNil(resolution.sourceName)
        XCTAssertTrue(resolution.isDefault)
        XCTAssertEqual(resolution.box, .bool(false))

        try local.setBox(.bool(true), for: "new-onboarding")

        resolution = flags.resolution(for: flags.flags.$newOnboarding)
        XCTAssertEqual(resolution.sourceName, "App Group")
        XCTAssertFalse(resolution.isDefault)
        XCTAssertEqual(resolution.box, .bool(true))
    }

    /// The diagnostics loop, which is the reason the by-key form exists.
    func testTheDiagnosticsLoopSample() throws {
        let local = SnapshotSource(name: "App Group")
        let flags = FlagPole(DocsAppFlags.self, sources: [local])
        try local.setBox(.int(50), for: "page-size")

        var report = [FlagKey: String]()
        for entry in flags.schema.flags {
            let resolution = flags.resolution(for: entry.key, as: entry.valueType)
            report[entry.key] = resolution.sourceName ?? "default"
        }

        XCTAssertEqual(report["page-size"], "App Group")
        XCTAssertEqual(report["new-onboarding"], "default")
    }

    /// The custom source sample.
    func testTheCustomSourceSample() {
        let firebase = FirebaseSource()
        let flags = FlagPole(DocsAppFlags.self, sources: [firebase])

        XCTAssertFalse(flags.newOnboarding)

        firebase.refresh(with: ["new-onboarding": .bool(true)])
        XCTAssertTrue(flags.newOnboarding)
        XCTAssertEqual(
            flags.resolution(for: flags.flags.$newOnboarding).sourceName,
            "Firebase"
        )
    }

    // MARK: - ObservingChanges.md

    /// The claim that a publisher emits the current value immediately, then on change.
    func testAPublisherEmitsCurrentValueThenChanges() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsAppFlags.self, sources: [local])

        var received = [Bool]()
        let cancellable = flags.flags.$newOnboarding.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        XCTAssertEqual(received, [false], "the current value arrives on subscription")

        try local.setBox(.bool(true), for: "new-onboarding")
        XCTAssertEqual(received, [false, true])
    }

    /// Where the `$` goes for a flag inside a group.
    func testTheProjectedValueOfANestedFlag() throws {
        let local = SnapshotSource()
        let flags = FlagPole(DocsAppFlags.self, sources: [local])

        var received = [Bool]()
        let cancellable = flags.flags.checkout.$applePay.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        try local.setBox(.bool(true), for: "checkout.apple-pay")
        XCTAssertEqual(received, [false, true])
    }

    // MARK: - RemoteOverrides.md

    /// The dot path sample, and the JSON quoted beside it.
    func testTheRemoteDotPathSample() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote])

        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )
        XCTAssertTrue(flags.newOnboarding)
    }

    /// The array-index path sample.
    func testAPathCanIndexIntoAnArray() throws {
        let remote = RemoteOverrideSource(DocsArrayPathFlags.self)
        let flags = FlagPole(DocsArrayPathFlags.self, sources: [remote])

        try remote.apply(Data(#"{"experiments": [{"enabled": true}]}"#.utf8), format: .json)
        XCTAssertTrue(flags.firstExperiment)
    }

    /// The claim that a flag with no remoteKey cannot be reached remotely.
    func testAFlagWithoutARemoteKeyIsNotRemotelyOverridable() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote])

        let result = try remote.apply(Data(#"{"page-size": 50}"#.utf8), format: .json)

        XCTAssertFalse(result.appliedKeys.contains("page-size"))
        XCTAssertFalse(result.absentKeys.contains("page-size"))
        XCTAssertEqual(flags.pageSize, 20)
    }

    /// What a successful apply reports.
    func testApplyReportsAppliedAndAbsentKeys() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)

        let result = try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )

        XCTAssertEqual(result.appliedKeys, ["new-onboarding"])
        XCTAssertEqual(result.absentKeys, ["checkout.apple-pay"])
    }

    /// The claim that applying replaces rather than merges.
    func testApplyingReplacesEverythingTheSourceHeld() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote])

        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )
        XCTAssertTrue(flags.newOnboarding)

        try remote.apply(Data(#"{"featureToggles": {}}"#.utf8), format: .json)
        XCTAssertFalse(flags.newOnboarding, "a flag the new payload omits stops being overridden")

        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )
        remote.clear()
        XCTAssertFalse(flags.newOnboarding)
    }

    /// The rejection sample: every problem at once, and nothing applied.
    func testRejectionReportsEveryProblemAndAppliesNothing() {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote])

        let data = Data(
            #"{"featureToggles": {"onboarding": {"v2": "yes"}, "checkout": {"applePay": 1}}}"#.utf8
        )

        XCTAssertThrowsError(try remote.apply(data, format: .json)) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.count, 2, "every problem is reported, not just the first")
            XCTAssertEqual(Set(problems.map(\.kind)), [.typeMismatch])
        }

        XCTAssertFalse(flags.newOnboarding)
        XCTAssertFalse(flags.checkout.applePay)
    }

    /// The custom mapper sample.
    func testTheCustomMapperSample() throws {
        let remote = RemoteOverrideSource(DocsExperimentFlags.self, mapper: ExperimentListMapper())
        let flags = FlagPole(DocsExperimentFlags.self, sources: [remote])

        let data = Data(
            """
            {
              "experiments": [
                { "name": "onboarding-v2", "state": "on" },
                { "name": "apple-pay",     "state": "off" }
              ]
            }
            """.utf8
        )
        try remote.apply(data, format: .json)

        XCTAssertTrue(flags.newOnboarding)
        XCTAssertFalse(flags.applePay)
    }

    /// The claim that a mapper's typo is reported rather than silently doing nothing.
    func testAMapperEmittingAnUnknownKeyIsReported() {
        let remote = RemoteOverrideSource(DocsAppFlags.self, mapper: TypoMapper())

        XCTAssertThrowsError(try remote.apply(Data("{}".utf8), format: .json)) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownFlag])
        }
    }

    /// The property list form.
    func testAPropertyListPayloadApplies() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote])

        let data = try PropertyListSerialization.data(
            fromPropertyList: ["featureToggles": ["onboarding": ["v2": true]]],
            format: .xml,
            options: 0
        )
        try remote.apply(data, format: .plist)

        XCTAssertTrue(flags.newOnboarding)
    }

    /// The key-encoding warning: both have to agree or nothing is ever found.
    func testTheRemoteSourceNeedsTheSameKeyEncoding() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self, keyEncoding: .snakecase)
        let flags = FlagPole(DocsAppFlags.self, sources: [remote], keyEncoding: .snakecase)

        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )
        XCTAssertTrue(flags.newOnboarding)

        let mismatched = RemoteOverrideSource(DocsAppFlags.self)
        let mismatchedFlags = FlagPole(DocsAppFlags.self, sources: [mismatched], keyEncoding: .snakecase)
        try mismatched.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )
        XCTAssertFalse(
            mismatchedFlags.newOnboarding,
            "a source keyed differently to its pole never gets asked for the key it holds"
        )
    }

    // MARK: - SharingWithACompanionApp.md

    /// The shape of the published document, as quoted in the article.
    func testThePublishedSchemaHasTheDocumentedShape() throws {
        let flags = FlagPole(
            DocsAppFlags.self, sources: [], applicationName: "Demo"
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: flags.schema.jsonData()) as? [String: Any]
        )

        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["applicationName"] as? String, "Demo")
        XCTAssertNotNil(object["generatedAt"] as? String)

        let entries = try XCTUnwrap(object["flags"] as? [[String: Any]])
        let applePay = try XCTUnwrap(entries.first { $0["key"] as? String == "checkout.apple-pay" })
        XCTAssertEqual(applePay["propertyPath"] as? [String], ["checkout", "applePay"])
        XCTAssertEqual(applePay["description"] as? String, "Offer Apple Pay")
        XCTAssertEqual(applePay["valueType"] as? String, "bool")
        XCTAssertEqual(applePay["defaultValue"] as? Bool, false)

        let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        let checkout = try XCTUnwrap(groups.first { ($0["propertyPath"] as? [String]) == ["checkout"] })
        XCTAssertEqual(checkout["description"] as? String, "Checkout")
    }

    /// `valueTypes`, which is what an importer validates against.
    func testASchemaCarriesTheTypesAnImportValidatesAgainst() {
        let schema = FlagPole(DocsAppFlags.self, sources: []).schema
        XCTAssertEqual(schema.valueTypes["page-size"], .int)
        XCTAssertEqual(schema.valueTypes["checkout.apple-pay"], .bool)
    }

    // MARK: - ExportingAndImporting.md

    /// The exported document, including the two claims made about its formatting.
    func testTheExportedDocumentMatchesWhatIsQuoted() throws {
        let flags = FlagPole(DocsEndpointFlags.self, sources: [SnapshotSource()])
        try flags.setOverride(true, for: flags.flags.$applePay)
        try flags.setOverride(URL(string: "https://staging.example.com/v3")!, for: flags.flags.$endpoint)

        let json = String(decoding: try flags.export(as: .json), as: UTF8.self)

        XCTAssertTrue(json.contains(#""apple-pay" : true"#), json)
        XCTAssertTrue(json.contains("https://staging.example.com/v3"), "slashes are not escaped")
        XCTAssertTrue(
            json.range(of: "apple-pay")!.lowerBound < json.range(of: "endpoint")!.lowerBound,
            "keys are sorted"
        )
    }

    /// Import returns what it applied.
    func testImportReportsWhatItApplied() throws {
        let source = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        try source.setOverride(50, for: source.flags.$pageSize)

        let destination = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        let result = try destination.importPayload(try source.export(as: .json), as: .json)

        XCTAssertEqual(result.appliedKeys, ["page-size"])
        XCTAssertEqual(destination.pageSize, 50)
    }

    /// The claim that import is not a wholesale replacement, and the clear-first recipe.
    func testImportLeavesUnmentionedOverridesAloneUnlessYouClearFirst() throws {
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        try flags.setOverride(true, for: flags.flags.$newOnboarding)

        let document = Data(#"{"formatVersion": 1, "values": {"page-size": 50}}"#.utf8)

        try flags.importPayload(document, as: .json)
        XCTAssertTrue(flags.newOnboarding, "an override the document does not mention survives")

        try flags.removeAllOverrides()
        try flags.importPayload(document, as: .json)
        XCTAssertFalse(flags.newOnboarding, "clearing first makes the document the whole state")
        XCTAssertEqual(flags.pageSize, 50)
    }

    /// The rejection sample.
    func testImportingAnUnknownKeyIsRejectedWholesale() throws {
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        let document = Data(
            #"{"formatVersion": 1, "values": {"page-size": 50, "not-a-flag": true}}"#.utf8
        )

        XCTAssertThrowsError(try flags.importPayload(document, as: .json)) { error in
            guard case let .rejected(problems) = error as? FlagImportError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownKey])
        }
        XCTAssertEqual(flags.pageSize, 20, "nothing is applied, not even the valid key")
    }

    /// The claim that an imported value outranks a later remote payload.
    func testAnImportedValueOutranksALaterRemotePayload() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource(), remote])

        try flags.importPayload(
            Data(#"{"formatVersion": 1, "values": {"new-onboarding": true}}"#.utf8), as: .json
        )
        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": false}}}"#.utf8), format: .json
        )

        XCTAssertTrue(flags.newOnboarding)
    }

    /// The QR sample, round-tripped.
    func testTheQRCodeSampleRoundTrips() throws {
        let source = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        try source.setOverride(true, for: source.flags.$newOnboarding)

        let string = try source.qrCodeString()
        XCTAssertTrue(string.hasPrefix("FFQR1:"))

        let destination = FlagPole(DocsAppFlags.self, sources: [SnapshotSource()])
        try destination.importQRCode(string)

        XCTAssertTrue(destination.newOnboarding)
    }

    /// The documented limit, and the error that carries what to remove.
    func testTheQRSizeErrorCarriesTheOverrideCount() throws {
        XCTAssertEqual(FlagQRCode.maximumEncodedLength, 2_953)

        let flags = FlagPole(DocsBlobFlags.self, sources: [SnapshotSource()])
        try flags.setOverride(incompressibleString(ofLength: 4_000), for: flags.flags.$blob)

        XCTAssertThrowsError(try flags.qrCodeString()) { error in
            guard case let .payloadTooLarge(bytes, limit, overrideCount) = error as? FlagQRCodeError
            else { return XCTFail("expected .payloadTooLarge, got \(error)") }
            XCTAssertGreaterThan(bytes, limit)
            XCTAssertEqual(overrideCount, 1)
        }
    }

    /// The claim that export spans the whole stack, remote values included.
    func testExportCarriesValuesARemotePayloadSupplied() throws {
        let remote = RemoteOverrideSource(DocsAppFlags.self)
        let flags = FlagPole(DocsAppFlags.self, sources: [SnapshotSource(), remote])

        try remote.apply(
            Data(#"{"featureToggles": {"onboarding": {"v2": true}}}"#.utf8), format: .json
        )

        let json = String(decoding: try flags.export(as: .json), as: UTF8.self)
        XCTAssertTrue(json.contains("new-onboarding"), json)
    }

    /// The non-finite error, which exists because the alternative kills the process.
    func testANonFiniteValueIsNamedRatherThanCrashing() throws {
        let flags = FlagPole(DocsCustomValueFlags.self, sources: [SnapshotSource()])
        try flags.setOverride(Percentage(amount: .infinity), for: flags.flags.$rollout)

        XCTAssertThrowsError(try flags.export(as: .json)) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("rollout"))
        }
    }

    // MARK: - SendingEvents.md

    /// The event enum samples: the default label, and a custom one.
    func testTheEventEnumSamples() {
        XCTAssertEqual(
            BareAppEvent.refetchRemoteConfiguration.eventDescription,
            "refetchRemoteConfiguration"
        )
        XCTAssertEqual(
            LabelledAppEvent.refetchRemoteConfiguration.eventDescription,
            "Re-fetch remote config"
        )
        XCTAssertEqual(BareAppEvent.allCases.count, 3)
    }

    /// Sending and receiving, over a suite standing in for an App Group.
    func testAnEventReachesAnObserver() throws {
        let suiteName = "docs.events.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let channel = FlagEventChannel(defaults: defaults, notificationName: suiteName)

        let received = expectation(description: "handled")
        let subscription = channel.observe(BareAppEvent.self) { event in
            XCTAssertEqual(event, .refetchRemoteConfiguration)
            received.fulfill()
        }

        channel.send(BareAppEvent.refetchRemoteConfiguration)

        wait(for: [received], timeout: 5)
        _ = subscription
    }

    // MARK: - Troubleshooting.md

    /// The five names dynamic member lookup cannot reach, and the way through.
    func testTheShadowedNamesAreReachableThroughTheContainer() {
        let flags = FlagPole(DocsShadowingFlags.self, sources: [])

        XCTAssertTrue(type(of: flags.schema) == FlagSchema.self, "the pole's own member wins")
        XCTAssertEqual(flags.flags.schema, "yours", "the flag is still reachable")
        XCTAssertTrue(type(of: flags.keys) == [FlagKey].self)
        XCTAssertTrue(type(of: flags.overrides) == [FlagKey: FlagValueBox].self)
        XCTAssertTrue(type(of: flags.descriptors) == [FlagDescriptor].self)
    }

    private func incompressibleString(ofLength count: Int) -> String {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var bytes = Data(count: count)
        for index in bytes.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return bytes.base64EncodedString()
    }
}

// MARK: - Fixtures, exactly as the articles write them

@FlagContainer
private struct DocsAppFlags {

    @Flag(
        default: false,
        description: "Show the redesigned onboarding",
        remoteKey: "featureToggles.onboarding.v2"
    )
    var newOnboarding: Bool

    @Flag(default: 20, description: "Items per page")
    var pageSize: Int

    @FlagGroup(description: "Checkout")
    var checkout: DocsCheckoutFlags
}

@FlagContainer
private struct DocsCheckoutFlags {

    @Flag(
        default: false,
        description: "Offer Apple Pay",
        remoteKey: "featureToggles.checkout.applePay"
    )
    var applePay: Bool

    @FlagGroup(description: "Express")
    var express: DocsExpressFlags
}

@FlagContainer
private struct DocsExpressFlags {

    @Flag(default: false, description: "One-tap purchase")
    var oneTap: Bool
}

@FlagContainer
private struct DocsAwkwardNameFlags {

    @Flag(default: false, description: "HTTPS only")
    var useHTTPSOnly: Bool

    @Flag(default: false, description: "Checkout v2")
    var checkoutV2: Bool
}

/// The detached-flag sample from DeclaringFlags.md.
private struct OnboardingPreviewFlags {

    @Flag(default: true, description: "Show the redesigned onboarding")
    var newOnboarding: Bool
}

/// The public-container sample from DeclaringFlags.md.
@FlagContainer
public struct DocsPublicFlags {

    @Flag(default: false, description: "Show the redesigned onboarding")
    public var newOnboarding: Bool
}

@FlagContainer
private struct DocsEveryTypeFlags {

    @Flag(default: false, description: "A switch")
    var enabled: Bool

    @Flag(default: 20, description: "A count")
    var pageSize: Int

    @Flag(default: 0.5, description: "A ratio")
    var rolloutShare: Double

    @Flag(default: 1.0, description: "A ratio, smaller")
    var scale: Float

    @Flag(default: "beta", description: "A name")
    var channel: String

    @Flag(default: Data(), description: "A blob")
    var payload: Data

    @Flag(default: .distantPast, description: "A moment")
    var launchesAt: Date

    @Flag(default: URL(string: "https://example.com")!, description: "An endpoint")
    var endpoint: URL
}

@FlagContainer
private struct DocsCollectionFlags {

    @Flag(default: [], description: "Markets to enable")
    var markets: [String]

    @Flag(default: [:], description: "Per-market rollout share")
    var rolloutByMarket: [String: Double]
}

private enum DocsTier: String, FlagValue, CaseIterable, FlagValueCases {
    case free, pro, enterprise
}

private enum DocsRetryPolicy: Int, FlagValue, CaseIterable, FlagValueCases {
    case none = 0, once = 1, aggressive = 3
}

@FlagContainer
private struct DocsEnumFlags {

    @Flag(default: DocsTier.free, description: "Pricing tier to present", remoteKey: "cfg.tier")
    var tier: DocsTier

    @Flag(default: DocsRetryPolicy.once, description: "Retry policy")
    var retryPolicy: DocsRetryPolicy
}

/// The custom `FlagValue` sample from FlagValues.md.
private struct Percentage: FlagValue {

    var amount: Double

    static var flagValueType: FlagValueType { .double }

    init(amount: Double) {
        self.amount = amount
    }

    init?(box: FlagValueBox) {
        guard case let .double(value) = box else { return nil }
        self.init(amount: value)
    }

    var box: FlagValueBox { .double(amount) }
}

@FlagContainer
private struct DocsCustomValueFlags {

    @Flag(default: Percentage(amount: 0), description: "Rollout share")
    var rollout: Percentage
}

/// The custom source sample from SourcesAndPrecedence.md.
private final class FirebaseSource: FlagValueSource, @unchecked Sendable {

    let sourceName = "Firebase"

    private let subject = PassthroughSubject<FlagChange, Never>()
    private var values: [FlagKey: FlagValueBox] = [:]

    func box(for key: FlagKey, as type: FlagValueType) -> FlagValueBox? {
        values[key]
    }

    var changes: AnyPublisher<FlagChange, Never> {
        subject.eraseToAnyPublisher()
    }

    func refresh(with values: [FlagKey: FlagValueBox]) {
        self.values = values
        subject.send(.all)
    }
}

@FlagContainer
private struct DocsArrayPathFlags {

    @Flag(default: false, description: "First experiment", remoteKey: "experiments.0.enabled")
    var firstExperiment: Bool
}

@FlagContainer
private struct DocsExperimentFlags {

    @Flag(default: false, description: "Onboarding", remoteKey: "onboarding-v2")
    var newOnboarding: Bool

    @Flag(default: false, description: "Apple Pay", remoteKey: "apple-pay")
    var applePay: Bool
}

/// The custom mapper sample from RemoteOverrides.md.
private struct ExperimentListMapper: RemoteOverrideMapper {

    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        guard case let .array(experiments)? = value.value(atPath: "experiments") else {
            throw RemoteOverrideError.malformed("expected an experiments array")
        }

        var states = [String: Bool]()
        for experiment in experiments {
            guard
                case let .string(name)? = experiment.value(atPath: "name"),
                case let .string(state)? = experiment.value(atPath: "state")
            else { continue }
            states[name] = state == "on"
        }

        return schema.flags.reduce(into: [:]) { result, entry in
            guard let remoteKey = entry.remoteKey, let state = states[remoteKey] else { return }
            result[entry.key] = .bool(state)
        }
    }
}

/// A mapper with the typo the article warns about.
private struct TypoMapper: RemoteOverrideMapper {

    func map(_ value: RemoteValue, schema: FlagSchema) throws -> [FlagKey: RemoteValue] {
        ["new-onbaording": .bool(true)]
    }
}

@FlagContainer
private struct DocsEndpointFlags {

    @Flag(default: false, description: "Offer Apple Pay")
    var applePay: Bool

    @Flag(default: URL(string: "https://example.com")!, description: "Endpoint")
    var endpoint: URL
}

@FlagContainer
private struct DocsBlobFlags {

    @Flag(default: "", description: "Blob")
    var blob: String
}

@FlagContainer
private struct DocsShadowingFlags {

    @Flag(default: "yours", description: "A flag called schema")
    var schema: String
}

/// The event samples from SendingEvents.md.
private enum BareAppEvent: String, FlagEvent {
    case refetchRemoteConfiguration
    case purgeImageCache
    case signOut
}

private enum LabelledAppEvent: String, FlagEvent {
    case refetchRemoteConfiguration
    case purgeImageCache

    var eventDescription: String {
        switch self {
        case .refetchRemoteConfiguration: return "Re-fetch remote config"
        case .purgeImageCache: return "Purge image cache"
        }
    }
}
