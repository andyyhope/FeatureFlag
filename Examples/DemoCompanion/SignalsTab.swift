import FeatureFlag
import SwiftUI

/// How long to wait between tapping a signal and sending it.
///
/// This is not a gimmick. A signal reaches a *running* host or nobody, and bringing the
/// companion to the front necessarily backgrounds the host — so a delay is how you tap
/// here, switch back to the app, and have the signal arrive once it is in front of you.
enum SignalDelay: TimeInterval, CaseIterable, Identifiable {

    case instant = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: TimeInterval { rawValue }

    var label: String {
        self == .instant ? "Instant" : "\(Int(rawValue))s"
    }
}

/// Signals the companion can send to the host app.
///
/// Flags change what the host *reads*; these ask it to *act*. Every send waits for the
/// host to confirm, because a Darwin notification has no delivery receipt — without
/// that, a press into a closed app would look exactly like a successful one.
struct SignalsTab: View {

    @State private var delay: SignalDelay = .instant
    @State private var pending: AppSignal?
    @State private var countdown: Double = 0
    @State private var pendingTask: Task<Void, Never>?
    @State private var inFlight: AppSignal?
    @State private var history: [Attempt] = []

    private let channel = FlagSignalChannel(appGroup: CompanionRootView.appGroup)

    private struct Attempt: Identifiable {
        let id = UUID()
        let signal: AppSignal
        let wasHandled: Bool
        let at: Date
    }

    var body: some View {
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
                ForEach(SignalDelay.allCases) { option in
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
            ForEach(AppSignal.allCases, id: \.self) { signal in
                Button {
                    tapped(signal)
                } label: {
                    HStack {
                        Text(signal.signalDescription)
                        Spacer(minLength: 8)
                        trailing(for: signal)
                    }
                }
                .disabled(channel == nil || (inFlight != nil) || (pending != nil && pending != signal))
            }
        } header: {
            Text("Send to the app")
        } footer: {
            Text(
                pending == nil
                    ? "Signals carry no payload. State belongs in flags, which you can "
                        + "already edit — “re-fetch for staging” is the environment flag, "
                        + "then a bare re-fetch."
                    : "Tap again to cancel."
            )
        }
    }

    @ViewBuilder
    private func trailing(for signal: AppSignal) -> some View {
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
                .accessibilityLabel("Sending in \(Int(delay.rawValue)) seconds. Tap to cancel.")
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

    private func tapped(_ signal: AppSignal) {
        if pending == signal {
            cancelPending()
        } else if delay == .instant {
            send(signal)
        } else {
            schedule(signal)
        }
    }

    private func schedule(_ signal: AppSignal) {
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

    private func send(_ signal: AppSignal) {
        guard let channel else { return }
        inFlight = signal

        Task {
            var handled = true
            do {
                try await channel.send(signal, timeout: 2)
            } catch {
                handled = false
            }
            history.insert(Attempt(signal: signal, wasHandled: handled, at: Date()), at: 0)
            history = Array(history.prefix(5))
            inFlight = nil
        }
    }
}
