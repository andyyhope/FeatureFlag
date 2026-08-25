// A test-only convenience. Add FeatureFlagTestSupport to a test target — never to an
// app target, which must not link XCTest. The core `FlagMappingAudit` lives in
// FeatureFlag itself and needs none of this; this only reports its verdict at the call
// site, the way an XCTAssert does.
#if canImport(XCTest)

    import FeatureFlag
    import Foundation
    import XCTest

    /// Fails the current test, at the call site, unless a payload wires up every flag it
    /// should.
    ///
    /// ```swift
    /// func testStagingConfigMapsEveryFlag() throws {
    ///     let json = try Data(contentsOf: fixture("staging.json"))
    ///     XCTAssertFlagsFullyMapped(AppFlags.self, applying: json)
    /// }
    /// ```
    ///
    /// The failure message is the whole audit — every absent flag, every mismatch, and,
    /// under `strict`, every value no flag reads — so a large config reports all of its
    /// problems at once rather than one per run.
    ///
    /// - Parameters:
    ///   - strict: Also require that every value in the payload is read by a flag.
    ///   - ignoring: Path prefixes whose unconsumed values are allowed under `strict` —
    ///     the metadata a file is expected to carry.
    public func XCTAssertFlagsFullyMapped<Root: FlagContainer>(
        _ type: Root.Type = Root.self,
        applying data: Data,
        format: FlagPayloadFormat = .json,
        mapper: any RemoteOverrideMapper = DotPathMapper(),
        keyEncoding: KeyEncoding = .kebabcase,
        strict: Bool = false,
        ignoring ignoredPrefixes: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let audit: FlagMappingAudit
        do {
            audit = try FlagMappingAudit(
                Root.self,
                applying: data,
                format: format,
                mapper: mapper,
                keyEncoding: keyEncoding
            )
        } catch {
            XCTFail("The payload could not be read: \(error)", file: file, line: line)
            return
        }

        if audit.isComplete(strict: strict, ignoring: ignoredPrefixes) == false {
            XCTFail(
                "\n" + audit.description(strict: strict, ignoring: ignoredPrefixes),
                file: file,
                line: line
            )
        }
    }
#endif
