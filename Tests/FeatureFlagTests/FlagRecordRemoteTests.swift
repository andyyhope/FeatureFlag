import XCTest

@testable import FeatureFlag

/// A backend sending a list of objects, for a flag that holds a list of records.
///
/// Records are stored as text, so without this a payload carrying the natural JSON
/// shape would be rejected as "not a string" — loudly, but for the wrong reason.
final class FlagRecordRemoteTests: XCTestCase {

    private func source() -> RemoteOverrideSource {
        RemoteOverrideSource(RemoteRecordFlags.self)
    }

    // MARK: - The shape a backend actually sends

    func testAListOfObjectsBecomesAListOfRecords() throws {
        let payload = """
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.example", "weight": 7, "tier": "beta" },
                { "name": "canary", "url": "https://canary.example", "weight": 3, "tier": "stable" }
            ] } }
            """

        let remote = source()
        let result = try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertEqual(result.appliedKeys, ["endpoints"])

        let pole = FlagPole(RemoteRecordFlags.self, sources: [remote])
        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["staging", "canary"])
        XCTAssertEqual(pole.flags.endpoints.values.map(\.weight), [7, 3])
        XCTAssertEqual(pole.flags.endpoints.values.first?.tier, .beta)
    }

    func testAnEmptyListIsAppliedRatherThanIgnored() throws {
        // Turning every endpoint off is a thing a backend does on purpose.
        let remote = source()
        try remote.apply(Data("""
            { "config": { "endpoints": [] } }
            """.utf8), format: .json)

        let pole = FlagPole(RemoteRecordFlags.self, sources: [remote])
        XCTAssertEqual(pole.flags.endpoints.values, [])
    }

    func testAPropertyListCarriesRecordsToo() throws {
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>config</key><dict><key>endpoints</key><array>
            <dict>
              <key>name</key><string>plist</string>
              <key>url</key><string>https://plist.example</string>
              <key>weight</key><integer>1</integer>
              <key>tier</key><string>stable</string>
            </dict>
            </array></dict></dict></plist>
            """

        let remote = source()
        try remote.apply(Data(plist.utf8), format: .plist)

        let pole = FlagPole(RemoteRecordFlags.self, sources: [remote])
        XCTAssertEqual(pole.flags.endpoints.values.map(\.name), ["plist"])
    }

    // MARK: - Strictness survives

    func testAFieldOfTheWrongTypeRejectsTheWholePayload() throws {
        let payload = """
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.example", "weight": "seven", "tier": "beta" }
            ] }, "featureToggles": { "onboarding": true } }
            """

        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json)) { error in
            guard case let RemoteOverrideError.rejected(problems) = error else {
                return XCTFail("expected a rejection, got \(error)")
            }
            XCTAssertEqual(problems.map(\.key), ["endpoints"])
            XCTAssertEqual(problems.first?.kind, .typeMismatch)
        }
    }

    func testAMissingFieldRejectsTheWholePayload() throws {
        let payload = """
            { "config": { "endpoints": [ { "name": "partial" } ] } }
            """

        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json))
    }

    func testAnEnumFieldTheAppCannotRepresentRejectsThePayload() throws {
        // The reason to check cases here rather than at read time: a backend adding a
        // tier an older build has never heard of should say so, not be discovered as a
        // flag that quietly stopped taking effect.
        let payload = """
            { "config": { "endpoints": [
                { "name": "x", "url": "https://x.example", "weight": 1, "tier": "experimental" }
            ] } }
            """

        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json))
    }

    func testSomethingThatIsNotAListAtAllIsRejected() throws {
        let payload = """
            { "config": { "endpoints": "not a list" } }
            """

        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json))
    }

    // MARK: - Nothing else changed

    func testOrdinaryFlagsStillWorkAlongside() throws {
        let payload = """
            { "config": { "endpoints": [
                { "name": "one", "url": "https://one.example", "weight": 1, "tier": "stable" }
            ] }, "featureToggles": { "onboarding": true } }
            """

        let remote = source()
        let result = try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertEqual(result.appliedKeys.sorted { $0.rawValue < $1.rawValue }, [
            "endpoints", "new-onboarding",
        ])

        let pole = FlagPole(RemoteRecordFlags.self, sources: [remote])
        XCTAssertTrue(pole.flags.newOnboarding)
    }

    func testARecordFlagWithNoRemoteKeyIsNotRemotelyOverridable() throws {
        let payload = """
            { "config": { "notes": [ { "text": "nope" } ] } }
            """

        let remote = source()
        let result = try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertFalse(result.appliedKeys.contains("notes"))
    }
}

// MARK: - Fixtures

private enum Tier: String, FlagValue, FlagValueCases, CaseIterable {
    case stable
    case beta
}

@FlagRecord
private struct Endpoint {
    var name: String
    var url: URL
    var weight: Int
    var tier: Tier
}

@FlagRecord
private struct Note {
    var text: String
}

@FlagContainer
private struct RemoteRecordFlags {

    @Flag(
        default: [
            Endpoint(name: "prod", url: URL(string: "https://prod.example")!, weight: 10, tier: .stable)
        ],
        description: "Endpoints",
        remoteKey: "config.endpoints"
    )
    var endpoints: FlagRecords<Endpoint>

    /// No `remoteKey`, so nothing a backend sends can touch it.
    @Flag(default: [], description: "Notes")
    var notes: FlagRecords<Note>

    @Flag(
        default: false,
        description: "Onboarding",
        remoteKey: "featureToggles.onboarding"
    )
    var newOnboarding: Bool
}
