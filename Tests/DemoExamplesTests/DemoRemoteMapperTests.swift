import FeatureFlag
import XCTest

@testable import DemoExamples

/// The demo's custom mapper, which exists because one of its payloads has a shape no
/// dot path can address.
final class DemoRemoteMapperTests: XCTestCase {

    private func makeSource() -> RemoteOverrideSource {
        RemoteOverrideSource(AppFlags.self, mapper: DemoRemoteMapper(), name: "Remote")
    }

    /// The reason the mapper exists: without it this payload applies cleanly and changes
    /// nothing, because no path addresses "the record whose flag is new-onboarding".
    func testTheDefaultMapperFindsNothingInARecordList() throws {
        let plain = RemoteOverrideSource(AppFlags.self, name: "Remote")
        let result = try plain.apply(RemoteConfiguration.records.data, format: .json)

        XCTAssertTrue(result.appliedKeys.isEmpty)
        XCTAssertNil(plain.box(for: "new-onboarding", as: .bool))
    }

    func testTheCustomMapperReshapesTheSamePayload() throws {
        let source = makeSource()
        let result = try source.apply(RemoteConfiguration.records.data, format: .json)

        XCTAssertEqual(Set(result.appliedKeys), ["new-onboarding", "checkout.apple-pay"])
        XCTAssertEqual(source.box(for: "new-onboarding", as: .bool), .bool(true))
        XCTAssertEqual(source.box(for: "checkout.apple-pay", as: .bool), .bool(true))
    }

    /// Composed, not replaced: the shape the backend used to send still works.
    func testTheOrdinaryDotPathPayloadsStillApply() throws {
        for configuration in [RemoteConfiguration.production, .staging, .local] {
            let source = makeSource()
            let result = try source.apply(configuration.data, format: .json)
            XCTAssertFalse(
                result.appliedKeys.isEmpty,
                "\(configuration.name) should still apply through the dot paths"
            )
        }
    }

    /// DotPathMapper cannot produce an unknown key — it only emits keys it read from the
    /// schema — so this problem kind is reachable only through a custom mapper. Which is
    /// exactly why it is reported rather than skipped.
    func testAMisspelledFlagIsReportedRatherThanIgnored() {
        XCTAssertThrowsError(
            try makeSource().apply(RemoteConfiguration.recordsWithATypo.data, format: .json)
        ) { error in
            guard case let .rejected(problems) = error as? RemoteOverrideError else {
                return XCTFail("expected .rejected, got \(error)")
            }
            XCTAssertEqual(problems.map(\.kind), [.unknownKey])
            XCTAssertEqual(problems.map(\.key), ["new-onbaording"])
        }
    }

    /// All-or-nothing, so the valid record beside the misspelled one is not applied.
    func testNothingIsAppliedWhenOneRecordIsWrong() {
        let source = makeSource()
        _ = try? source.apply(RemoteConfiguration.recordsWithATypo.data, format: .json)
        XCTAssertNil(source.box(for: "checkout.apple-pay", as: .bool))
    }

    func testARecordMissingItsFieldsIsSkippedRatherThanCrashing() throws {
        let source = makeSource()
        let payload = Data(#"{"experiments": [{"flag": "new-onboarding"}, {"enabled": true}]}"#.utf8)

        let result = try source.apply(payload, format: .json)
        XCTAssertTrue(result.appliedKeys.isEmpty)
    }
}
