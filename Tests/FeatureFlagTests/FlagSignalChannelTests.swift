import XCTest

@testable import FeatureFlag

/// iOS gives third-party apps no XPC and no way to wake another app, so this is built
/// from an App Group and a Darwin notification. These exercise both halves in one
/// process, which is what two apps sharing a group amount to.
final class FlagSignalChannelTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var notificationName = ""

    override func setUp() {
        super.setUp()
        suiteName = "com.featureflag.signals.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        notificationName = "\(suiteName).signal"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeChannel() -> FlagSignalChannel {
        FlagSignalChannel(defaults: defaults, notificationName: notificationName)
    }

    // MARK: - Delivery

    func testASignalReachesAnObserver() {
        let companion = makeChannel()
        let host = makeChannel()

        let received = expectation(description: "signal")
        var seen: TestSignal?
        let subscription = host.observe(TestSignal.self) { signal in
            seen = signal
            received.fulfill()
        }
        defer { _ = subscription }

        companion.send(TestSignal.refetch)

        wait(for: [received], timeout: 5)
        XCTAssertEqual(seen, .refetch)
    }

    func testEachSignalArrivesAsItself() {
        let companion = makeChannel()
        let host = makeChannel()

        var seen: [TestSignal] = []
        let received = expectation(description: "all three")
        received.expectedFulfillmentCount = 3
        let lock = NSLock()

        let subscription = host.observe(TestSignal.self) { signal in
            lock.lock()
            seen.append(signal)
            lock.unlock()
            received.fulfill()
        }
        defer { _ = subscription }

        for signal in TestSignal.allCases {
            companion.send(signal)
            // Serialised: one record holds one signal, so the host must see each before
            // the next replaces it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        wait(for: [received], timeout: 10)
        XCTAssertEqual(Set(seen), Set(TestSignal.allCases))
    }

    func testNothingArrivesAfterTheSubscriptionIsReleased() {
        let companion = makeChannel()
        let host = makeChannel()

        let fired = expectation(description: "should not fire")
        fired.isInverted = true
        do {
            let subscription = host.observe(TestSignal.self) { _ in fired.fulfill() }
            _ = subscription
        }

        companion.send(TestSignal.refetch)
        wait(for: [fired], timeout: 1.5)
    }

    // MARK: - Delivered at most once

    func testARepeatedBellDoesNotRunTheSignalTwice() {
        // Darwin notifications can arrive more than once for a single post. Re-running
        // "purge the cache" because the OS coalesced differently would be its own bug.
        let companion = makeChannel()
        let host = makeChannel()

        var count = 0
        let lock = NSLock()
        let subscription = host.observe(TestSignal.self) { _ in
            lock.lock()
            count += 1
            lock.unlock()
        }
        defer { _ = subscription }

        companion.send(TestSignal.refetch)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        // Ring again with no new signal recorded.
        DarwinNotificationCenter.post(notificationName)
        DarwinNotificationCenter.post(notificationName)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        lock.lock()
        let total = count
        lock.unlock()
        XCTAssertEqual(total, 1)
    }

    func testAHostThatStartsLateDoesNotReplayOldSignals() {
        // The signal is lost rather than queued: a host that was not running when it was
        // sent must not act on it minutes later, when it is no longer what anyone wants.
        let companion = makeChannel()
        companion.send(TestSignal.refetch)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let host = makeChannel()
        let fired = expectation(description: "should not replay")
        fired.isInverted = true
        let subscription = host.observe(TestSignal.self) { _ in fired.fulfill() }
        defer { _ = subscription }

        wait(for: [fired], timeout: 1.5)
    }

    // MARK: - Acknowledgement

    func testSendingWithATimeoutSucceedsWhenTheHostIsListening() async throws {
        let companion = makeChannel()
        let host = makeChannel()

        let subscription = host.observe(TestSignal.self) { _ in }
        defer { _ = subscription }

        try await companion.send(TestSignal.refetch, timeout: 5)
    }

    func testSendingWithATimeoutReportsWhenNothingIsListening() async {
        let companion = makeChannel()

        do {
            try await companion.send(TestSignal.refetch, timeout: 1)
            XCTFail("should not have been acknowledged")
        } catch {
            XCTAssertEqual(error as? FlagSignalError, .notAcknowledged)
        }
    }

    func testASignalThisBuildCannotRepresentIsNotAcknowledged() async {
        // A newer companion sending a case an older host does not have. Skipping it is
        // right — an app cannot perform a command it does not know — but telling the
        // sender it was handled would be a lie.
        let companion = makeChannel()
        let host = makeChannel()

        let subscription = host.observe(NarrowSignal.self) { _ in
            XCTFail("unknown signal should not be handled")
        }
        defer { _ = subscription }

        do {
            try await companion.send(TestSignal.purgeCache, timeout: 1)
            XCTFail("should not have been acknowledged")
        } catch {
            XCTAssertEqual(error as? FlagSignalError, .notAcknowledged)
        }
    }

    func testAnUnknownSignalDoesNotBlockTheNextValidOne() async throws {
        let companion = makeChannel()
        let host = makeChannel()

        let received = expectation(description: "valid signal")
        let subscription = host.observe(NarrowSignal.self) { _ in received.fulfill() }
        defer { _ = subscription }

        companion.send(TestSignal.purgeCache)  // unknown to NarrowSignal
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        try await companion.send(TestSignal.refetch, timeout: 5)
        await fulfillment(of: [received], timeout: 5)
    }

    // MARK: - Declaring signals

    func testSignalsDescribeThemselvesForAButton() {
        XCTAssertEqual(TestSignal.refetch.signalDescription, "Re-fetch remote configuration")
        // Without an explicit description, the raw value stands in.
        XCTAssertEqual(NarrowSignal.refetch.signalDescription, "refetch")
    }

    func testTheSignalListIsDiscoverable() {
        XCTAssertEqual(
            TestSignal.allCases.map(\.rawValue),
            ["refetch", "purgeCache", "dumpDiagnostics"]
        )
    }

    // MARK: - App Group

    func testAChannelIsNilWhenTheAppGroupIsUnavailable() {
        let identifier = Bundle.main.bundleIdentifier ?? "xctest"
        XCTAssertNil(FlagSignalChannel(appGroup: identifier))
    }
}

// MARK: - Fixtures

private enum TestSignal: String, FlagSignal {
    case refetch
    case purgeCache
    case dumpDiagnostics

    var signalDescription: String {
        switch self {
        case .refetch: return "Re-fetch remote configuration"
        case .purgeCache: return "Purge cached responses"
        case .dumpDiagnostics: return "Write diagnostics"
        }
    }
}

/// Stands in for an older host build that knows fewer cases.
private enum NarrowSignal: String, FlagSignal {
    case refetch
}

// MARK: - More than one observer

/// A host that groups its signals declares several enums and observes each of them.
/// Until this worked, whichever observer woke first claimed the event, failed to
/// represent it, and dropped it — so the second group's signals were silently lost.
final class MultipleObserverTests: XCTestCase {

    fileprivate func makeChannel() throws -> (FlagSignalChannel, String, UserDefaults) {
        let suiteName = "signals.multi.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (
            FlagSignalChannel(defaults: defaults, notificationName: suiteName),
            suiteName,
            defaults
        )
    }

    func testEachObserverReceivesItsOwnSignals() throws {
        let (channel, suiteName, defaults) = try makeChannel()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cacheArrived = expectation(description: "cache")
        let sessionArrived = expectation(description: "session")

        let a = channel.observe(GroupedCacheSignal.self) { signal in
            XCTAssertEqual(signal, .purgeImages)
            cacheArrived.fulfill()
        }
        let b = channel.observe(GroupedSessionSignal.self) { signal in
            XCTAssertEqual(signal, .signOut)
            sessionArrived.fulfill()
        }

        channel.send(GroupedSessionSignal.signOut)
        wait(for: [sessionArrived], timeout: 5)

        channel.send(GroupedCacheSignal.purgeImages)
        wait(for: [cacheArrived], timeout: 5)

        _ = (a, b)
    }

    /// An observer must not consume an event it cannot represent, but it must still not
    /// run the same one twice when the OS coalesces a notification.
    func testAnObserverStillRunsEachSignalOnlyOnce() throws {
        let (channel, suiteName, defaults) = try makeChannel()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let arrived = expectation(description: "once")
        arrived.expectedFulfillmentCount = 1
        arrived.assertForOverFulfill = true

        let subscription = channel.observe(GroupedCacheSignal.self) { _ in arrived.fulfill() }

        channel.send(GroupedCacheSignal.purgeImages)
        DarwinNotificationCenter.post(suiteName)
        DarwinNotificationCenter.post(suiteName)

        wait(for: [arrived], timeout: 5)
        _ = subscription
    }

    /// The acknowledgement has to mean "something handled it". It used to be recorded
    /// before the type was checked, so a host observing only one group reported success
    /// for a signal from another that it had actually dropped.
    func testASignalNoObserverCanRepresentIsNotAcknowledged() async throws {
        let (channel, suiteName, defaults) = try makeChannel()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let subscription = channel.observe(GroupedCacheSignal.self) { _ in
            XCTFail("this observer cannot represent a session signal")
        }

        do {
            try await channel.send(GroupedSessionSignal.signOut, timeout: 1)
            XCTFail("expected .notAcknowledged")
        } catch {
            XCTAssertEqual(error as? FlagSignalError, .notAcknowledged)
        }
        _ = subscription
    }
}

private enum GroupedCacheSignal: String, FlagSignal {
    case purgeImages
}

private enum GroupedSessionSignal: String, FlagSignal {
    case signOut
}

// MARK: - requiresRestart

extension MultipleObserverTests {

    func testASignalDoesNotRequireARestartUnlessItSaysSo() {
        XCTAssertFalse(GroupedCacheSignal.purgeImages.requiresRestart)
    }

    func testASignalCanSayItNeedsARestart() {
        XCTAssertTrue(RestartingSignal.swapDependency.requiresRestart)
        XCTAssertFalse(RestartingSignal.harmless.requiresRestart)
    }

    /// It is declarative only — delivery is unaffected, because whether the effect is
    /// visible yet is not something the channel can know.
    func testRequiringARestartDoesNotChangeDelivery() throws {
        let (channel, suiteName, defaults) = try makeChannel()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let arrived = expectation(description: "arrived")
        let subscription = channel.observe(RestartingSignal.self) { signal in
            XCTAssertEqual(signal, .swapDependency)
            arrived.fulfill()
        }

        channel.send(RestartingSignal.swapDependency)
        wait(for: [arrived], timeout: 5)
        _ = subscription
    }
}

private enum RestartingSignal: String, FlagSignal {
    case swapDependency
    case harmless

    var requiresRestart: Bool { self == .swapDependency }
}
