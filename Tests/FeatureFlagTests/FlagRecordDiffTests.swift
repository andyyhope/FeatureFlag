import Foundation
import XCTest

@testable import FeatureFlag

/// A record flag's default-vs-config diff, broken down per record and per field instead
/// of two truncated JSON blobs.
final class FlagRecordDiffTests: XCTestCase {

    private func audit(_ json: String) throws -> FlagMappingAudit {
        try FlagMappingAudit(RecordDiffFlags.self, applying: Data(json.utf8))
    }

    private func endpoints(_ audit: FlagMappingAudit) throws -> FlagDefaultComparison {
        try XCTUnwrap(audit.defaults.first { $0.key == "endpoints" })
    }

    // MARK: - One field of one record

    func testAChangedFieldIsNamedWithBothValues() throws {
        // Default has staging → https://staging.a ; config changes only its url.
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.b", "weight": 1 }
            ] } }
            """)
        let diff = try endpoints(audit)
        let record = try XCTUnwrap(diff.records?.first { $0.identifier == "staging" })

        guard case let .changed(fields) = record.change else {
            return XCTFail("expected a changed record, got \(record.change)")
        }
        let url = try XCTUnwrap(fields.first { $0.field == "url" })
        XCTAssertEqual(url.defaultValue, .url(URL(string: "https://staging.a")!))
        XCTAssertEqual(url.incomingValue, .url(URL(string: "https://staging.b")!))
        XCTAssertNil(fields.first { $0.field == "weight" }, "an unchanged field is not listed")
    }

    // MARK: - Added and removed records

    func testARecordOnlyInTheConfigIsAdded() throws {
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.a", "weight": 1 },
                { "name": "canary", "url": "https://canary.a", "weight": 2 }
            ] } }
            """)
        let record = try XCTUnwrap(try endpoints(audit).records?.first { $0.identifier == "canary" })

        XCTAssertEqual(record.change, .added)
    }

    func testARecordOnlyInTheDefaultIsRemoved() throws {
        // Default has staging and prod; config drops prod.
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.a", "weight": 1 }
            ] } }
            """)
        let record = try XCTUnwrap(try endpoints(audit).records?.first { $0.identifier == "prod" })

        XCTAssertEqual(record.change, .removed)
    }

    // MARK: - Index pairing when there is no key

    func testAKeylessRecordListPairsByIndex() throws {
        let audit = try audit("""
            { "config": { "ports": [ { "host": "a", "port": 443 } ] } }
            """)
        let ports = try XCTUnwrap(audit.defaults.first { $0.key == "ports" })
        let record = try XCTUnwrap(ports.records?.first)

        XCTAssertEqual(record.identifier, "[0]")
        guard case let .changed(fields) = record.change else {
            return XCTFail("expected a changed record, got \(record.change)")
        }
        XCTAssertEqual(fields.first { $0.field == "port" }?.incomingValue, .int(443))
    }

    // MARK: - Reordering

    func testAReorderedListSaysSoRatherThanDumpingTheBlob() throws {
        // Same records, different order. The stored value differs, so it is a change —
        // but no record was added, removed, or edited. It must not fall back to the two
        // truncated JSON strings the structured diff exists to replace.
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "prod", "url": "https://prod.a", "weight": 3 },
                { "name": "staging", "url": "https://staging.a", "weight": 1 }
            ] } }
            """)

        XCTAssertEqual(try endpoints(audit).records, [], "no record changed, only order")
        XCTAssertTrue(audit.changesDefault.contains("endpoints"), "order is a real change")
        XCTAssertTrue(audit.defaultsDescription.contains("reordered"), audit.defaultsDescription)
        XCTAssertFalse(audit.defaultsDescription.contains(#""url":"#), audit.defaultsDescription)
    }

    // MARK: - Matching and non-record flags

    func testARecordListRestatedExactlyHasNoRecordChanges() throws {
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.a", "weight": 1 },
                { "name": "prod", "url": "https://prod.a", "weight": 3 }
            ] } }
            """)

        XCTAssertEqual(try endpoints(audit).records, [])
        XCTAssertTrue(audit.matchesDefault.contains("endpoints"))
    }

    func testAScalarFlagHasNoRecordBreakdown() throws {
        let audit = try audit("""
            { "config": { "pageSize": 99, "endpoints": [
                { "name": "staging", "url": "https://staging.a", "weight": 1 },
                { "name": "prod", "url": "https://prod.a", "weight": 3 }
            ] } }
            """)

        XCTAssertNil(audit.defaults.first { $0.key == "page-size" }?.records)
    }

    // MARK: - Reporting

    func testTheDescriptionShowsFieldsNotATruncatedBlob() throws {
        // staging changed, canary added, prod dropped — all three kinds at once.
        let audit = try audit("""
            { "config": { "endpoints": [
                { "name": "staging", "url": "https://staging.b", "weight": 1 },
                { "name": "canary", "url": "https://canary.a", "weight": 9 }
            ] } }
            """)
        let text = audit.defaultsDescription

        XCTAssertTrue(text.contains("~ staging"), text)              // changed
        XCTAssertTrue(text.contains("https://staging.a"), text)      // old value, in full
        XCTAssertTrue(text.contains("https://staging.b"), text)      // new value, in full
        XCTAssertTrue(text.contains("+ canary"), text)               // added
        XCTAssertTrue(text.contains("- prod"), text)                 // removed
        XCTAssertFalse(text.contains(#""url":"#), text)              // not raw JSON
    }
}

// MARK: - Fixtures

@FlagRecord
private struct Endpoint {
    @FlagRecordKey var name: String
    var url: URL
    var weight: Int
}

@FlagRecord
private struct Port {
    var host: String
    var port: Int
}

@FlagContainer
private struct RecordDiffFlags {

    @Flag(
        default: [
            Endpoint(name: "staging", url: URL(string: "https://staging.a")!, weight: 1),
            Endpoint(name: "prod", url: URL(string: "https://prod.a")!, weight: 3),
        ],
        description: "Endpoints",
        remoteKey: "config.endpoints"
    )
    var endpoints: FlagRecords<Endpoint>

    @Flag(
        default: [Port(host: "a", port: 80)],
        description: "Ports",
        remoteKey: "config.ports"
    )
    var ports: FlagRecords<Port>

    @Flag(default: 10, description: "Page size", remoteKey: "config.pageSize")
    var pageSize: Int
}
