import XCTest

@testable import FeatureFlag

/// Records that have to match a real backend: a field the payload omits or sends as
/// `null`, and a field whose JSON key is not the Swift property name.
final class FlagRecordOptionalAndKeyTests: XCTestCase {

    private func source() -> RemoteOverrideSource {
        RemoteOverrideSource(PayFlags.self)
    }

    private func pole(_ remote: RemoteOverrideSource) -> FlagPole<PayFlags> {
        FlagPole(PayFlags.self, sources: [remote])
    }

    // MARK: - Optional fields, decoded from a remote payload

    func testAnOmittedOptionalFieldDecodesAsNil() throws {
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "card", "apple_pay": false }
            ] } }
            """
        let remote = source()
        try remote.apply(Data(payload.utf8), format: .json)

        let method = pole(remote).flags.paymentMethods.values.first
        XCTAssertEqual(method?.name, "card")
        XCTAssertNil(method?.minimumSpend, "an omitted optional field is nil, not a rejection")
    }

    func testAnExplicitNullOptionalFieldDecodesAsNil() throws {
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "card", "apple_pay": false, "minimumSpend": null }
            ] } }
            """
        let remote = source()
        try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertNil(pole(remote).flags.paymentMethods.values.first?.minimumSpend)
    }

    func testAPresentOptionalFieldDecodesToItsValue() throws {
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "wallet", "apple_pay": true, "minimumSpend": 10.5 }
            ] } }
            """
        let remote = source()
        try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertEqual(pole(remote).flags.paymentMethods.values.first?.minimumSpend, 10.5)
    }

    func testAnOptionalFieldOfTheWrongTypeStillRejects() throws {
        // Optional means "may be absent", not "any type accepted".
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "card", "apple_pay": false, "minimumSpend": "lots" }
            ] } }
            """
        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json))
    }

    // MARK: - Custom decode key

    func testACustomKeyIsReadFromThePayload() throws {
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "wallet", "apple_pay": true }
            ] } }
            """
        let remote = source()
        try remote.apply(Data(payload.utf8), format: .json)

        XCTAssertEqual(pole(remote).flags.paymentMethods.values.first?.applePay, true,
                       "the field is read from apple_pay, not applePay")
    }

    func testThePropertyNameIsNotReadWhenACustomKeyIsSet() throws {
        // The backend uses apple_pay; a payload using the Swift name should not satisfy
        // the field, so a bool with no default rejects the payload.
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "wallet", "applePay": true }
            ] } }
            """
        XCTAssertThrowsError(try source().apply(Data(payload.utf8), format: .json))
    }

    func testTheStoredFormIsCanonical() throws {
        // Custom key is decode-only: once decoded, the record is stored under the Swift
        // property name and with nil optionals omitted.
        let payload = """
            { "config": { "paymentMethods": [
                { "name": "wallet", "apple_pay": true }
            ] } }
            """
        let remote = source()
        try remote.apply(Data(payload.utf8), format: .json)

        guard case let .string(json) = pole(remote).flags.paymentMethods.box else {
            return XCTFail("a record list is stored as text")
        }
        XCTAssertTrue(json.contains("applePay"), "stored under the property name")
        XCTAssertFalse(json.contains("apple_pay"), "not the backend's key")
        XCTAssertFalse(json.contains("minimumSpend"), "a nil optional is omitted, not stored as null")
    }

    // MARK: - Diffing an optional field

    func testADiffShowsAnOptionalFieldGainingAValue() {
        // nil in the default, a value in the config: a per-field change, shown as the
        // field going from unset to that value.
        let shape = PaymentMethod.flagRecordShape
        let base = [PaymentMethod(name: "card", applePay: false, minimumSpend: nil).flagRecordBoxes]
        let incoming = [
            PaymentMethod(name: "card", applePay: false, minimumSpend: 10).flagRecordBoxes
        ]

        let diffs = FlagRecordDiff.diff(default: base, incoming: incoming, shape: shape)

        guard case let .changed(fields) = diffs.first?.change else {
            return XCTFail("expected a changed record, got \(String(describing: diffs.first?.change))")
        }
        XCTAssertEqual(fields.map(\.field), ["minimumSpend"])
        XCTAssertNil(fields.first?.defaultValue, "unset in the default")
        XCTAssertEqual(fields.first?.incomingValue, .double(10))
    }

    // MARK: - Round-trip through storage

    func testAnOptionalNilRoundTripsThroughTheBox() {
        let method = PaymentMethod(name: "card", applePay: false, minimumSpend: nil)
        let list = FlagRecords<PaymentMethod>([method])

        let restored = FlagRecords<PaymentMethod>(box: list.box)

        XCTAssertEqual(restored?.values, [method])
        XCTAssertNil(restored?.values.first?.minimumSpend)
    }
}

// MARK: - Fixtures

@FlagRecord
private struct PaymentMethod {
    @FlagRecordKey var name: String
    @FlagRecordProperty(key: "apple_pay") var applePay: Bool
    var minimumSpend: Double?
}

@FlagContainer
private struct PayFlags {
    @Flag(default: [], description: "Payment methods", remoteKey: "config.paymentMethods")
    var paymentMethods: FlagRecords<PaymentMethod>
}
