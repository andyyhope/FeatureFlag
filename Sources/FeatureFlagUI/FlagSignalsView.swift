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
    /// ```swift
    /// FlagSignalsView(AppSignal.self, appGroup: "group.com.example.flags")
    /// ```
    ///
    /// Give it groups when there are enough signals to be worth filing:
    ///
    /// ```swift
    /// FlagSignalsView(
    ///     groups: [
    ///         .group("Caches", CacheSignal.self),
    ///         .group("Session", SessionSignal.self),
    ///     ],
    ///     appGroup: "group.com.example.flags"
    /// )
    /// ```
    ///
    /// Every send waits for the host to confirm, because a Darwin notification has no
    /// delivery receipt — without that, a press into a closed app would look exactly like
    /// a successful one.
    public struct FlagSignalsView: View {

        @StateObject private var model: FlagSignalsModel
        private let groups: [FlagSignalGroup]

        /// - Parameters:
        ///   - groups: Shown in the order given. A group is laid out flat or on its own
        ///     screen according to its ``FlagSignalGroupDisplay``.
        ///   - appGroup: The group the host also declares.
        ///   - timeout: How long to wait for the host to acknowledge before calling it
        ///     unhandled.
        public init(groups: [FlagSignalGroup], appGroup: String, timeout: TimeInterval = 2) {
            // Two groups defining the same raw value is a declaration mistake with no
            // correct behaviour: a signal travels as its raw value, so the host's
            // observers would both fire for one press.
            precondition(
                groups.duplicateSignalID == nil,
                """
                More than one signal group defines \
                '\(groups.duplicateSignalID ?? "")'. A signal travels as its raw value, \
                so it has to be unique across every group.
                """
            )

            self.groups = groups
            self._model = StateObject(
                wrappedValue: FlagSignalsModel(appGroup: appGroup, timeout: timeout)
            )
        }

        /// Every case of one signal type, in a single flat list.
        public init<Signal: FlagSignal>(
            _ type: Signal.Type = Signal.self,
            appGroup: String,
            timeout: TimeInterval = 2
        ) {
            self.init(
                groups: [FlagSignalGroup.group("", type, display: .flat)],
                appGroup: appGroup,
                timeout: timeout
            )
        }

        public var body: some View {
            NavigationStack {
                Form {
                    FlagSignalDelayPicker(model: model)

                    ForEach(groups.filter { $0.isNested == false }) { group in
                        FlagSignalListSection(model: model, group: group)
                    }

                    let nested = groups.filter(\.isNested)
                    if nested.isEmpty == false {
                        Section("Groups") {
                            ForEach(nested) { group in
                                NavigationLink {
                                    FlagSignalGroupScreen(model: model, group: group)
                                } label: {
                                    LabeledContent(group.title) {
                                        Text("\(group.signals.count)")
                                    }
                                }
                            }
                        }
                    }

                    FlagSignalHistorySection(model: model)

                    if model.channel == nil {
                        Section {
                            Text("The App Group is unavailable, so there is nowhere to send.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Signals")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            .onDisappear { model.cancelPending() }
        }
    }

    // MARK: - One group's own screen

    struct FlagSignalGroupScreen: View {

        @ObservedObject var model: FlagSignalsModel
        let group: FlagSignalGroup

        var body: some View {
            Form {
                // Repeated rather than left behind on the previous screen: the delay is
                // the mechanism, and having to go back to change it would defeat it.
                FlagSignalDelayPicker(model: model)
                FlagSignalListSection(model: model, group: group, showsHeader: false)
                FlagSignalHistorySection(model: model)
            }
            .navigationTitle(group.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Pieces

    struct FlagSignalDelayPicker: View {

        @ObservedObject var model: FlagSignalsModel

        var body: some View {
            Section {
                Picker("Delay", selection: $model.delay) {
                    ForEach(FlagSignalDelay.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.pending != nil)
            } header: {
                Text("Delay")
            } footer: {
                Text(
                    model.delay == .instant
                        ? "Sent the moment you tap. The app has to be running to hear it, and "
                            + "opening this one puts it in the background."
                        : "Tap a signal, then switch to the app. It fires when the circle "
                            + "completes, by which time the app is in front and listening."
                )
            }
        }
    }

    struct FlagSignalListSection: View {

        @ObservedObject var model: FlagSignalsModel
        let group: FlagSignalGroup
        var showsHeader = true

        var body: some View {
            Section {
                ForEach(group.signals) { signal in
                    Button {
                        model.tapped(signal)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.description)
                                if signal.requiresRestart {
                                    Text("Takes effect after a relaunch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            trailing(for: signal)
                        }
                    }
                    .disabled(model.isDisabled(signal))
                }
            } header: {
                if showsHeader, group.title.isEmpty == false {
                    Text(group.title)
                }
            } footer: {
                if showsHeader, group.title.isEmpty {
                    Text(
                        model.pending == nil
                            ? "Signals carry no payload. State belongs in flags, which you "
                                + "can already edit."
                            : "Tap again to cancel."
                    )
                }
            }
        }

        @ViewBuilder
        private func trailing(for signal: ErasedSignal) -> some View {
            if model.inFlight == signal {
                ProgressView()
            } else if model.pending == signal {
                Circle()
                    .trim(from: 0, to: model.countdown)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
                    .overlay { Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3) }
                    .accessibilityLabel(
                        "Sending in \(Int(model.delay.rawValue)) seconds. Tap to cancel."
                    )
            } else {
                Image(systemName: "paperplane").foregroundStyle(.tint)
            }
        }
    }

    struct FlagSignalHistorySection: View {

        @ObservedObject var model: FlagSignalsModel

        var body: some View {
            if model.history.isEmpty == false {
                Section("Recent") {
                    ForEach(model.history) { attempt in
                        LabeledContent {
                            Text(attempt.outcome)
                                .foregroundStyle(attempt.wasHandled ? .green : .orange)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attempt.signal.description)
                                Text(attempt.at.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: - State

    /// Delay, countdown, what is in flight and what happened.
    ///
    /// Held apart from the views because a nested group is a second screen, and pushing
    /// one must not lose a scheduled send or the history of what came back.
    @MainActor
    final class FlagSignalsModel: ObservableObject {

        @Published var delay: FlagSignalDelay = .instant
        @Published var pending: ErasedSignal?
        @Published var countdown: Double = 0
        @Published var inFlight: ErasedSignal?
        @Published var history: [Attempt] = []

        let channel: FlagSignalChannel?
        private let timeout: TimeInterval
        private var pendingTask: Task<Void, Never>?

        init(appGroup: String, timeout: TimeInterval) {
            self.channel = FlagSignalChannel(appGroup: appGroup)
            self.timeout = timeout
        }

        struct Attempt: Identifiable {
            let id = UUID()
            let signal: ErasedSignal
            let wasHandled: Bool
            let at: Date

            /// "Handled" is not the whole truth for a signal whose effect waits for a
            /// relaunch, and saying only that invites "nothing happened".
            var outcome: String {
                switch (wasHandled, signal.requiresRestart) {
                case (true, true): return "handled — relaunch to see it"
                case (true, false): return "handled"
                case (false, _): return "no response"
                }
            }
        }

        func isDisabled(_ signal: ErasedSignal) -> Bool {
            channel == nil || inFlight != nil || (pending != nil && pending != signal)
        }

        func tapped(_ signal: ErasedSignal) {
            if pending == signal {
                cancelPending()
            } else if delay == .instant {
                send(signal)
            } else {
                schedule(signal)
            }
        }

        private func schedule(_ signal: ErasedSignal) {
            pending = signal
            countdown = 0
            withAnimation(.linear(duration: delay.rawValue)) { countdown = 1 }

            pendingTask = Task { [delay] in
                try? await Task.sleep(nanoseconds: UInt64(delay.rawValue * 1_000_000_000))
                guard Task.isCancelled == false else { return }
                pending = nil
                countdown = 0
                send(signal)
            }
        }

        func cancelPending() {
            pendingTask?.cancel()
            pendingTask = nil
            pending = nil
            withAnimation(.easeOut(duration: 0.15)) { countdown = 0 }
        }

        private func send(_ signal: ErasedSignal) {
            guard let channel else { return }
            inFlight = signal

            Task { [timeout] in
                var handled = true
                do {
                    try await signal.send(over: channel, timeout: timeout)
                } catch {
                    handled = false
                }
                history.insert(
                    Attempt(signal: signal, wasHandled: handled, at: Date()), at: 0
                )
                history = Array(history.prefix(5))
                inFlight = nil
            }
        }
    }

#endif
