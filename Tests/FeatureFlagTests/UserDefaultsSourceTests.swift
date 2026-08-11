import Combine
import XCTest

@testable import FeatureFlag

final class UserDefaultsSourceTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        suiteName = "com.featureflag.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        cancellables.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeSource() -> UserDefaultsSource {
        UserDefaultsSource(defaults: defaults, name: "local")
    }

    // MARK: - Natural storage

    func testStoresPrimitivesAsThemselves() throws {
        // Values must be readable by anything that opens the suite — `defaults read`,
        // another framework, an older build. So they are stored natively, not boxed.
        let source = makeSource()
        try source.setBox(.bool(true), for: "flag.bool")
        try source.setBox(.int(7), for: "flag.int")
        try source.setBox(.double(1.5), for: "flag.double")
        try source.setBox(.string("hi"), for: "flag.string")

        XCTAssertEqual(defaults.object(forKey: "flag.bool") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "flag.int") as? Int, 7)
        XCTAssertEqual(defaults.object(forKey: "flag.double") as? Double, 1.5)
        XCTAssertEqual(defaults.object(forKey: "flag.string") as? String, "hi")
    }

    func testStoresURLAsAString() throws {
        let source = makeSource()
        try source.setBox(.url(URL(string: "https://example.com")!), for: "flag.url")

        XCTAssertEqual(defaults.object(forKey: "flag.url") as? String, "https://example.com")
    }

    // MARK: - Round trips

    func testEverySupportedTypeRoundTrips() throws {
        let source = makeSource()
        let cases: [(FlagValueBox, FlagValueType)] = [
            (.bool(true), .bool),
            (.int(-7), .int),
            (.double(3.5), .double),
            (.float(2.5), .float),
            (.string("hello"), .string),
            (.data(Data([0x01, 0x02])), .data),
            (.date(Date(timeIntervalSince1970: 1_000)), .date),
            (.url(URL(string: "https://example.com/a?b=c")!), .url),
            (.array([.int(1), .int(2)]), .array(.int)),
            (.dictionary(["a": .string("x")]), .dictionary(.string)),
            (.array([.array([.bool(true)])]), .array(.array(.bool))),
        ]

        // A distinct key per type, because UserDefaults caches a key's CoreFoundation
        // type within a process and a real flag never changes type at runtime anyway.
        for (index, (box, type)) in cases.enumerated() {
            let key = FlagKey("round.trip.\(index)")
            try source.setBox(box, for: key)
            XCTAssertEqual(source.box(for: key, as: type), box, "failed for \(type)")
        }
    }

    func testReadingWithTheWrongTypeYieldsNothing() throws {
        let source = makeSource()
        try source.setBox(.string("not a number"), for: "flag.value")

        XCTAssertNil(source.box(for: "flag.value", as: .int))
        XCTAssertNil(source.box(for: "flag.value", as: .date))
    }

    func testNumericTypesDoNotSilentlyConvert() throws {
        // UserDefaults hands back NSNumber for booleans, integers and doubles alike.
        // Truncating 3.5 into an Int flag, or reading 1 as `true`, would be a silent
        // wrong answer rather than a fall-through to the next source.
        let source = makeSource()

        try source.setBox(.double(3.5), for: "flag.double")
        XCTAssertNil(source.box(for: "flag.double", as: .int))

        try source.setBox(.int(1), for: "flag.int")
        XCTAssertNil(source.box(for: "flag.int", as: .bool))

        try source.setBox(.bool(true), for: "flag.bool")
        XCTAssertNil(source.box(for: "flag.bool", as: .int))
    }

    func testMissingKeyYieldsNothing() {
        XCTAssertNil(makeSource().box(for: "absent", as: .bool))
    }

    func testSettingNilRemovesTheValue() throws {
        let source = makeSource()
        try source.setBox(.bool(true), for: "flag.bool")
        try source.setBox(nil, for: "flag.bool")

        XCTAssertNil(source.box(for: "flag.bool", as: .bool))
        XCTAssertNil(defaults.object(forKey: "flag.bool"))
    }

    func testAdoptsValuesWrittenByOtherCode() {
        // A team migrating from hand-rolled UserDefaults flags should find them working.
        defaults.set(true, forKey: "already.here")
        XCTAssertEqual(makeSource().box(for: "already.here", as: .bool), .bool(true))
    }

    // MARK: - Change notification

    func testWritingEmitsAChangeForThatKey() throws {
        let source = makeSource()
        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        try source.setBox(.bool(true), for: "flag.bool")
        XCTAssertEqual(changes, [.keys(["flag.bool"])])
    }

    func testRefreshEmitsAWholesaleChange() {
        let source = makeSource()
        var changes: [FlagChange] = []
        source.changes.sink { changes.append($0) }.store(in: &cancellables)

        source.refresh()
        XCTAssertEqual(changes, [.all])
    }
}
