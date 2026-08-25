import FeatureFlag
import FeatureFlagTestSupport
import XCTest

@testable import DemoExamples

/// The pattern to copy for a real config: point the audit at each bundled payload and
/// let it check, in both directions, that the file wires up every flag.
///
/// The forward `absentKeys` checks elsewhere in this suite catch a path that matches
/// nothing. This is the reverse — a value in the file that no flag reads — and the two
/// together are what make a large config trustworthy without tracing it by hand.
final class ConfigurationAuditTests: XCTestCase {

    private let payloads: [RemoteConfiguration] = [.production, .staging, .local]

    func testEveryBundledPayloadWiresUpEveryFlagItProvides() throws {
        for config in payloads {
            let audit = try FlagMappingAudit(AppFlags.self, applying: config.data)
            XCTAssertTrue(audit.isComplete, "\(config.name):\n\(audit)")
        }
    }

    /// These payloads are hand-authored for this app alone, so nothing in them should go
    /// unread — strict passes with no exceptions. A real backend config would list its
    /// metadata prefixes in `ignoring:`.
    func testEveryBundledPayloadIsFullyConsumed() throws {
        for config in payloads {
            XCTAssertFlagsFullyMapped(
                AppFlags.self, applying: config.data, strict: true
            )
        }
    }

    /// A record flag pulls a whole subtree — the audit must count every leaf beneath
    /// `config.paymentMethods` as read, or staging would look full of unconsumed values.
    func testTheRecordListSubtreeCountsAsConsumed() throws {
        let audit = try FlagMappingAudit(AppFlags.self, applying: RemoteConfiguration.staging.data)

        XCTAssertTrue(audit.applied.contains("payment-methods"))
        XCTAssertEqual(audit.unconsumed.filter { $0.contains("paymentMethods") }, [])
    }

    /// A path typo is invisible at apply time. The audit names it from both sides.
    func testAMisspelledPathIsCaughtAsAbsentAndUnconsumed() throws {
        let broken = RemoteConfiguration.staging.json.replacingOccurrences(
            of: "\"apiEndpoint\"", with: "\"api_endpoint\""
        )

        let audit = try FlagMappingAudit(AppFlags.self, applying: Data(broken.utf8))

        XCTAssertTrue(audit.absent.contains("checkout.endpoint"), "\(audit)")
        XCTAssertTrue(audit.unconsumed.contains("config.api_endpoint"), "\(audit)")
        XCTAssertFalse(audit.isComplete)
    }
}
