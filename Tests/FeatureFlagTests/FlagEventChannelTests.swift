import XCTest

@testable import FeatureFlag

/// iOS gives third-party apps no XPC and no way to wake another app, so this is built
/// from an App Group and a Darwin notification. These exercise both halves in one
/// process, which is what two apps sharing a group amount to.
final class FlagEventChannelTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var notificationName = ""

    override func setUp() {
        super.setUp()
        suiteName = "com.featureflag.events.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        notificationName = "\(suiteName).event"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeChannel() -> FlagEventChannel {
        FlagEventChannel(defaults: defaults, notificationName: notificationName)
    }

    // MARK: - Delivery

    func testAnEventReachesAnObserver() {
        let companion = makeChannel()
        let host = makeChannel()

        let received = expectation(description: "event")
        var seen: TestEvent?
        let subscription = host.observe(TestEvent.self) { event in
            seen = event
            received.fulfill()
        }
        defer { _ = subscription }

        companion.send(TestEvent.refetch)

        wait(for: [received], timeout: 5)
        XCTAssertEqual(seen, .refetch)
    }

    func testEachEventArrivesAsItself() {
        let companion = makeChannel()
        let host = makeChannel()

        var seen: [TestEvent] = []
        let received = expectation(description: "all three")
        received.expectedFulfillmentCount = 3
        let lock = NSLock()

        let subscription = host.observe(TestEvent.self) { event in
            lock.lock()
            seen.append(event)
            lock.unlock()
            received.fulfill()
        }
        defer { _ = subscription }

        for event in TestEvent.allCases {
            companion.send(event)
            // Serialised: one record holds one event, so the host must see each before
            // the next replaces it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        wait(for: [received], timeout: 10)
        XCTAssertEqual(Set(seen), Set(TestEvent.allCases))
    }

    func testNothingArrivesAfterTheSubscriptionIsReleased() {
        let companion = makeChannel()
        let host = makeChannel()

        let fired = expectation(description: "should not fire")
        fired.isInverted = true
        do {
            let subscription = host.observe(TestEvent.self) { _ in fired.fulfill() }
            _ = subscription
        }

        companion.send(TestEvent.refetch)
        wait(for: [fired], timeout: 1.5)
    }

    // MARK: - Delivered at most once

    func testARepeatedBellDoesNotRunTheEventTwice() {
        // Darwin notifications can arrive more than once for a single post. Re-running
        // "purge the cache" because the OS coalesced differently would be its own bug.
        let companion = makeChannel()
        let host = makeChannel()

        var count = 0
        let lock = NSLock()
        let subscription = host.observe(TestEvent.self) { _ in
            lock.lock()
            count += 1
            lock.unlock()
        }
        defer { _ = subscription }

        companion.send(TestEvent.refetch)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        // Ring again with no new event recorded.
        DarwinNotificationCenter.post(notificationName)
        DarwinNotificationCenter.post(notificationName)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        lock.lock()
        let total = count
        lock.unlock()
        XCTAssertEqual(total, 1)
    }

    func testAHostThatStartsLateDoesNotReplayOldEvents() {
        // The event is lost rather than queued: a host that was not running when it was
        // sent must not act on it minutes later, when it is no longer what anyone wants.
        let companion = makeChannel()
        companion.send(TestEvent.refetch)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let host = makeChannel()
        let fired = expectation(description: "should not replay")
        fired.isInverted = true
        let subscription = host.observe(TestEvent.self) { _ in fired.fulfill() }
        defer { _ = subscription }

        wait(for: [fired], timeout: 1.5)
    }

    // MARK: - Acknowledgement

    func testSendingWithATimeoutSucceedsWhenTheHostIsListening() async throws {
        let companion = makeChannel()
        let host = makeChannel()

        let subscription = host.observe(TestEvent.self) { _ in }
        defer { _ = subscription }

        try await companion.send(TestEvent.refetch, timeout: 5)
    }

    func testSendingWithATimeoutReportsWhenNothingIsListening() async {
        let companion = makeChannel()

        do {
            try await companion.send(TestEvent.refetch, timeout: 1)
            XCTFail("should not have been acknowledged")
        } catch {
            XCTAssertEqual(error as? FlagEventError, .notAcknowledged)
        }
    }

    func testAnEventThisBuildCannotRepresentIsNotAcknowledged() async {
        // A newer companion sending a case an older host does not have. Skipping it is
        // right — an app cannot perform a command it does not know — but telling the
        // sender it was handled would be a lie.
        let companion = makeChannel()
        let host = makeChannel()

        let subscription = host.observe(NarrowEvent.self) { _ in
            XCTFail("unknown event should not be handled")
        }
        defer { _ = subscription }

        do {
            try await companion.send(TestEvent.purgeCache, timeout: 1)
            XCTFail("should not have been acknowledged")
        } catch {
            XCTAssertEqual(error as? FlagEventError, .notAcknowledged)
        }
    }

    func testAnUnknownEventDoesNotBlockTheNextValidOne() async throws {
        let companion = makeChannel()
        let host = makeChannel()

        let received = expectation(description: "valid event")
        let subscription = host.observe(NarrowEvent.self) { _ in received.fulfill() }
        defer { _ = subscription }

        companion.send(TestEvent.purgeCache)  // unknown to NarrowEvent
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        try await companion.send(TestEvent.refetch, timeout: 5)
        await fulfillment(of: [received], timeout: 5)
    }

    // MARK: - Declaring events

    func testEventsDescribeThemselvesForAButton() {
        XCTAssertEqual(TestEvent.refetch.eventDescription, "Re-fetch remote configuration")
        // Without an explicit description, the raw value stands in.
        XCTAssertEqual(NarrowEvent.refetch.eventDescription, "refetch")
    }

    func testTheEventListIsDiscoverable() {
        XCTAssertEqual(
            TestEvent.allCases.map(\.rawValue),
            ["refetch", "purgeCache", "dumpDiagnostics"]
        )
    }

    // MARK: - App Group

    func testAChannelIsNilWhenTheAppGroupIsUnavailable() {
        let identifier = Bundle.main.bundleIdentifier ?? "xctest"
        XCTAssertNil(FlagEventChannel(appGroup: identifier))
    }
}

// MARK: - Fixtures

private enum TestEvent: String, FlagEvent {
    case refetch
    case purgeCache
    case dumpDiagnostics

    var eventDescription: String {
        switch self {
        case .refetch: return "Re-fetch remote configuration"
        case .purgeCache: return "Purge cached responses"
        case .dumpDiagnostics: return "Write diagnostics"
        }
    }
}

/// Stands in for an older host build that knows fewer cases.
private enum NarrowEvent: String, FlagEvent {
    case refetch
}
