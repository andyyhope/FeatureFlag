import Combine
import XCTest

@testable import FeatureFlag

/// iOS does not tell one process when another writes to a shared `UserDefaults` suite:
/// `UserDefaults.didChangeNotification` stays silent for external writes. Darwin
/// notifications do cross the boundary, and are how a companion app's edit reaches the
/// host app while it is running.
final class DarwinNotificationTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testPostedNotificationReachesAnObserver() {
        let name = "com.featureflag.tests.\(UUID().uuidString)"
        let received = expectation(description: "darwin notification")

        let observer = DarwinNotificationCenter.observe(name) { received.fulfill() }
        defer { _ = observer }

        DarwinNotificationCenter.post(name)
        wait(for: [received], timeout: 5)
    }

    func testObserverStopsAfterItIsReleased() {
        let name = "com.featureflag.tests.\(UUID().uuidString)"
        let fired = expectation(description: "should not fire")
        fired.isInverted = true

        do {
            let observer = DarwinNotificationCenter.observe(name) { fired.fulfill() }
            _ = observer
        }

        DarwinNotificationCenter.post(name)
        wait(for: [fired], timeout: 1)
    }

    func testOneSourceSeesAnotherSourceWriteToTheSharedSuite() throws {
        // Stands in for the two-process case: the companion app writes, the host app
        // finds out. Both sides use the same App Group suite and notification name.
        let suiteName = "com.featureflag.tests.\(UUID().uuidString)"
        let notificationName = "\(suiteName).changed"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let host = UserDefaultsSource(
            defaults: defaults,
            name: "host",
            crossProcessNotificationName: notificationName
        )
        let companion = UserDefaultsSource(
            defaults: defaults,
            name: "companion",
            crossProcessNotificationName: notificationName
        )

        let hostNoticed = expectation(description: "host noticed")
        host.changes
            .sink { change in
                if change == .all { hostNoticed.fulfill() }
            }
            .store(in: &cancellables)

        try companion.setBox(.bool(true), for: "new-onboarding")

        wait(for: [hostNoticed], timeout: 5)
        XCTAssertEqual(host.box(for: "new-onboarding", as: .bool), .bool(true))
    }
}
