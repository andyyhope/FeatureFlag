#if os(iOS)

    import ActivityKit
    import SwiftUI
    import UIKit
    import WidgetKit

    /// A delayed signal, as a Live Activity. ``FlagSignalsView`` starts one for every
    /// delayed send; ``FlagSignalLiveActivity`` draws it.
    @available(iOS 16.2, *)
    struct FlagSignalActivityAttributes: ActivityAttributes {

        /// Nothing changes while the countdown runs: everything it shows is known at the
        /// tap, and the system animates the ring from the dates alone.
        struct ContentState: Codable, Hashable {}

        /// What the signal is called on its button.
        let signal: String

        /// From the tap to the moment the signal fires.
        let interval: ClosedRange<Date>
    }

    /// The Live Activity for a delayed signal: a ring in the Dynamic Island that drains
    /// until the signal fires.
    ///
    /// Add it to a widget extension in your companion app, and set
    /// `NSSupportsLiveActivities` to `YES` in the companion's Info.plist:
    ///
    /// ```swift
    /// import FeatureFlagUI
    /// import SwiftUI
    /// import WidgetKit
    ///
    /// @main
    /// struct CompanionWidgets: WidgetBundle {
    ///     var body: some Widget {
    ///         FlagSignalLiveActivity()
    ///     }
    /// }
    /// ```
    ///
    /// Without both, delayed sends work exactly as before; there is just nothing to see
    /// outside the companion.
    @available(iOS 16.2, *)
    public struct FlagSignalLiveActivity: Widget {

        public init() {}

        public var body: some WidgetConfiguration {
            ActivityConfiguration(for: FlagSignalActivityAttributes.self) { context in
                HStack(spacing: 12) {
                    DrainingRing(interval: context.attributes.interval)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.signal).font(.headline)
                        Text("Sending in \(Text(timerInterval: context.attributes.interval))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        DrainingRing(interval: context.attributes.interval)
                            .frame(width: 32, height: 32)
                    }
                    DynamicIslandExpandedRegion(.center) {
                        Text(context.attributes.signal)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        Text(timerInterval: context.attributes.interval)
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                } compactLeading: {
                    Image(systemName: "paperplane.fill").foregroundStyle(.tint)
                } compactTrailing: {
                    DrainingRing(interval: context.attributes.interval)
                } minimal: {
                    DrainingRing(interval: context.attributes.interval)
                }
            }
        }
    }

    /// Counts down, so it empties as the send approaches. The system animates it from
    /// the interval; the companion does not need to be running to keep it moving.
    @available(iOS 16.2, *)
    private struct DrainingRing: View {

        let interval: ClosedRange<Date>

        var body: some View {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(.accentColor)
        }
    }

    /// Keeps a delayed send alive, and in view, while the companion is in the background.
    ///
    /// Switching to the host app is the point of the delay, and a suspended companion
    /// cannot send: a few seconds after it leaves the screen, its countdown stops until
    /// it is reopened. The background task buys the time the longest delay needs.
    @MainActor
    final class FlagSignalKeepAlive {

        private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        private var activity: Any?

        func begin(_ signal: ErasedSignal, countdown: FlagSignalCountdown) {
            end()
            backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "Sending \(signal.description)"
            ) { [weak self] in
                // Out of time, so the send will not go until the companion is reopened.
                // A ring left counting down would say otherwise.
                self?.expire()
            }

            if #available(iOS 16.2, *) {
                // Left behind by a companion that was killed mid-countdown, and nothing
                // else will ever end it.
                for stale in Activity<FlagSignalActivityAttributes>.activities {
                    Task { await stale.end(nil, dismissalPolicy: .immediate) }
                }

                // Throws when Live Activities are switched off, or the companion has no
                // widget extension to show one. Either way the send goes ahead unseen.
                activity = try? Activity.request(
                    attributes: FlagSignalActivityAttributes(
                        signal: signal.description,
                        interval: countdown.interval
                    ),
                    content: ActivityContent(
                        state: FlagSignalActivityAttributes.ContentState(),
                        staleDate: countdown.interval.upperBound
                    )
                )
            }
        }

        func end() {
            let activity = self.activity
            let backgroundTask = self.backgroundTask
            self.activity = nil
            self.backgroundTask = .invalid

            // The background task outlives the activity: released first, the companion
            // could be suspended before the end reached the system, leaving a finished
            // countdown in the Dynamic Island until it was next opened.
            Task {
                if #available(iOS 16.2, *),
                    let activity = activity as? Activity<FlagSignalActivityAttributes>
                {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }

        /// The expiration handler has to release the task before it returns, so the
        /// activity's end cannot be waited for here.
        private func expire() {
            if #available(iOS 16.2, *),
                let activity = activity as? Activity<FlagSignalActivityAttributes>
            {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            activity = nil
            guard backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

#endif
