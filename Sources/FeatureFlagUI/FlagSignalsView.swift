#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// How long to wait between tapping a signal and sending it.
    ///
    /// Not a gimmick. A signal reaches a *running* host or nobody, and bringing the
    /// companion to the front necessarily backgrounds the host — so a delay is how you
    /// tap here, switch back to the app, and have the signal arrive once it is in front
    /// of you. Without it, every send from a foregrounded companion races the host's
    /// suspension.
    public enum FlagSignalDelay: TimeInterval, CaseIterable, Identifiable, Sendable {

        case instant = 0
        case three = 3
        case five = 5
        case ten = 10

        public var id: TimeInterval { rawValue }

        public var label: String {
            self == .instant ? "Instant" : "\(Int(rawValue))s"
        }
    }

    /// Sends an app's signals to its host, and says whether they arrived.
    ///
    /// Generic over your own signal type, so the list is whatever you declared:
    ///
    /// ```swift
    /// enum AppSignal: String, FlagSignal {
    ///     case refetchRemoteConfiguration
    ///     case purgeImageCache
    /// }
    ///
    /// FlagSignalsView(AppSignal.self, appGroup: "group.com.example.flags")
    /// ```
    ///
    /// Every send waits for the host to confirm, because a Darwin notification has no
    /// delivery receipt — without that, a press into a closed app would look exactly like
    /// a successful one.
    public struct FlagSignalsView<Signal: FlagSignal>: View {

        @State private var delay: FlagSignalDelay = .instant
        @State private var pending: Signal?
        @State private var countdown: Double = 0
        @State private var pendingTask: Task<Void, Never>?
        @State private var inFlight: Signal?
        @State private var history: [Attempt] = []

        private let channel: FlagSignalChannel?
        private let timeout: TimeInterval

        /// - Parameters:
        ///   - type: Your signal enum. Its `allCases` become the list.
        ///   - appGroup: The group the host also declares.
        ///   - timeout: How long to wait for the host to acknowledge before calling it
        ///     unhandled. Two seconds is long enough for a foregrounded app and short
        ///     enough that a closed one does not leave someone staring at a spinner.
        public init(_ type: Signal.Type = Signal.self, appGroup: String, timeout: TimeInterval = 2) {
            self.channel = FlagSignalChannel(appGroup: appGroup)
            self.timeout = timeout
        }

        private struct Attempt: Identifiable {
            let id = UUID()
            let signal: Signal
            let wasHandled: Bool
            let at: Date
        }

        public var body: some View {
            NavigationStack {
                Form {
                    delaySection
                    signalsSection
                    if history.isEmpty == false { historySection }
                    if channel == nil { unavailableSection }
                }
                .navigationTitle("Signals")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            .onDisappear { cancelPending() }
        }

        // MARK: - Delay

        private var delaySection: some View {
            Section {
                Picker("Delay", selection: $delay) {
                    ForEach(FlagSignalDelay.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(pending != nil)
            } header: {
                Text("Delay")
            } footer: {
                Text(
                    delay == .instant
                        ? "Sent the moment you tap. The app has to be running to hear it, and "
                            + "opening this one puts it in the background."
                        : "Tap a signal, then switch to the app. It fires when the circle "
                            + "completes, by which time the app is in front and listening."
                )
            }
        }

        // MARK: - Signals

        private var signalsSection: some View {
            Section {
                ForEach(Array(Signal.allCases), id: \.self) { signal in
                    Button {
                        tapped(signal)
                    } label: {
                        HStack {
                            Text(signal.signalDescription)
                            Spacer(minLength: 8)
                            trailing(for: signal)
                        }
                    }
                    .disabled(
                        channel == nil || (inFlight != nil) || (pending != nil && pending != signal)
                    )
                }
            } header: {
                Text("Send to the app")
            } footer: {
                Text(
                    pending == nil
                        ? "Signals carry no payload. State belongs in flags, which you can "
                            + "already edit — \u{201C}re-fetch for staging\u{201D} is a flag, "
                            + "then a bare re-fetch."
                        : "Tap again to cancel."
                )
            }
        }

        @ViewBuilder
        private func trailing(for signal: Signal) -> some View {
            if inFlight == signal {
                ProgressView()
            } else if pending == signal {
                Circle()
                    .trim(from: 0, to: countdown)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                    }
                    .accessibilityLabel(
                        "Sending in \(Int(delay.rawValue)) seconds. Tap to cancel."
                    )
            } else {
                Image(systemName: "paperplane").foregroundStyle(.tint)
            }
        }

        private var historySection: some View {
            Section("Recent") {
                ForEach(history) { attempt in
                    LabeledContent {
                        Text(attempt.wasHandled ? "handled" : "no response")
                            .foregroundStyle(attempt.wasHandled ? .green : .orange)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attempt.signal.signalDescription)
                            Text(attempt.at.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }
        }

        private var unavailableSection: some View {
            Section {
                Text("The App Group is unavailable, so there is nowhere to send.")
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: - Sending

        private func tapped(_ signal: Signal) {
            if pending == signal {
                cancelPending()
            } else if delay == .instant {
                send(signal)
            } else {
                schedule(signal)
            }
        }

        private func schedule(_ signal: Signal) {
            pending = signal
            countdown = 0
            withAnimation(.linear(duration: delay.rawValue)) { countdown = 1 }

            pendingTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay.rawValue * 1_000_000_000))
                guard Task.isCancelled == false else { return }
                pending = nil
                countdown = 0
                send(signal)
            }
        }

        private func cancelPending() {
            pendingTask?.cancel()
            pendingTask = nil
            pending = nil
            withAnimation(.easeOut(duration: 0.15)) { countdown = 0 }
        }

        private func send(_ signal: Signal) {
            guard let channel else { return }
            inFlight = signal

            Task {
                var handled = true
                do {
                    try await channel.send(signal, timeout: timeout)
                } catch {
                    handled = false
                }
                history.insert(Attempt(signal: signal, wasHandled: handled, at: Date()), at: 0)
                history = Array(history.prefix(5))
                inFlight = nil
            }
        }
    }

#endif
