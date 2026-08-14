// The editor is an iOS and macOS surface. watchOS has no Menu, TextEditor or
// bordered text field, and a flag-editing companion on a watch is not a real use case;
// tvOS has no text entry worth the name. The core FeatureFlag module supports every
// platform — this is only the UI.
#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// A whole companion app, given an App Group.
    ///
    /// ```swift
    /// @main
    /// struct CompanionApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             FlagCompanionView(appGroup: "group.com.example.flags")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// That is the entire app: opening the shared store, reporting the two ways it can
    /// fail, and tabs for what you have changed and what you can change. None of it is
    /// specific to any host, so none of it is worth copying into every companion.
    ///
    /// Pass a closure to lay the tabs out yourself — you are handed the loaded store, so
    /// you can order the built-in views however you like and add your own beside them:
    ///
    /// ```swift
    /// FlagCompanionView(appGroup: "group.com.example.flags") { store in
    ///     FlagOverridesView(store: store)
    ///         .flagCompanionTab("Overrides", symbol: "dial.medium", isSelected: true)
    ///
    ///     MySignalsTab()
    ///         .flagCompanionTab("Signals", symbol: "paperplane", isSelected: false)
    /// }
    /// ```
    public struct FlagCompanionView<Content: View>: View {

        private let appGroup: String
        private let content: (FlagEditingStore) -> Content

        @StateObject private var loader: FlagCompanionLoader

        /// - Parameters:
        ///   - appGroup: The identifier both this app and the host declare in their
        ///     entitlements. It is the only thing the two share.
        ///   - content: Builds the body once the store is open. Omit it for the default
        ///     two tabs.
        public init(
            appGroup: String,
            @ViewBuilder content: @escaping (FlagEditingStore) -> Content
        ) {
            self.appGroup = appGroup
            self.content = content
            self._loader = StateObject(wrappedValue: FlagCompanionLoader(appGroup: appGroup))
        }

        public var body: some View {
            switch loader.state {
            case .loading:
                ProgressView()
                    .task { loader.load() }

            case let .ready(store):
                content(store)

            case let .failed(message):
                FlagCompanionUnavailableView(message: message) { loader.load() }
            }
        }
    }

    extension FlagCompanionView where Content == FlagCompanionTabs {

        /// A companion built from a list of tabs.
        ///
        /// Defaults to overrides and the whole flag tree, which is every companion's
        /// minimum. Add a `signals` tab if your app has signals, leave it out if it does not, and put them in whatever order reads
        /// best.
        public init(appGroup: String, tabs: [FlagCompanionTab] = [.overrides, .flags]) {
            self.init(appGroup: appGroup) { store in
                FlagCompanionTabs(store: store, tabs: tabs)
            }
        }
    }

    // MARK: - Tabs

    /// One tab in a companion, chosen rather than written.
    ///
    /// Companions differ in what they need: one app has signals to send, another has a
    /// screen built around a single flag, most want neither. Composing a list keeps the
    /// choice — and the order — yours without any of them reimplementing the shell:
    ///
    /// ```swift
    /// FlagCompanionView(
    ///     appGroup: "group.com.example.flags",
    ///     tabs: [.overrides, .signals(AppSignal.self), .flags]
    /// )
    /// ```
    public struct FlagCompanionTab: Identifiable {

        public let id: String
        let title: String
        let symbol: String
        let content: (FlagEditingStore) -> AnyView

        init(
            id: String,
            title: String,
            symbol: String,
            content: @escaping (FlagEditingStore) -> AnyView
        ) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.content = content
        }
    }

    extension FlagCompanionTab {

        /// What has been changed, and the ways it leaves the device.
        public static var overrides: FlagCompanionTab {
            FlagCompanionTab(id: "overrides", title: "Overrides", symbol: "dial.medium") {
                AnyView(FlagOverridesView(store: $0))
            }
        }

        /// Every flag the host published, grouped and searchable.
        public static var flags: FlagCompanionTab {
            FlagCompanionTab(id: "flags", title: "Flags", symbol: "flag") {
                AnyView(FlagBrowserView(store: $0))
            }
        }

        /// One-way instructions to a running host. Omit it if your app has none — the
        /// tab needs your signal enum, so there is nothing sensible to show without one.
        public static func signals<Signal: FlagSignal>(
            _ type: Signal.Type,
            appGroup: String,
            title: String = "Signals",
            symbol: String = "paperplane"
        ) -> FlagCompanionTab {
            FlagCompanionTab(id: "signals", title: title, symbol: symbol) { _ in
                AnyView(FlagSignalsView(Signal.self, appGroup: appGroup))
            }
        }

        /// Signals filed into groups, for an app with enough of them to be worth it.
        ///
        /// Each group is its own enum, so the host still switches over one at a time,
        /// exhaustively — see ``FlagSignalGroup``.
        public static func signals(
            _ groups: [FlagSignalGroup],
            appGroup: String,
            title: String = "Signals",
            symbol: String = "paperplane"
        ) -> FlagCompanionTab {
            FlagCompanionTab(id: "signals", title: title, symbol: symbol) { _ in
                AnyView(FlagSignalsView(groups: groups, appGroup: appGroup))
            }
        }

        /// One flag on a screen of its own, for the one whose consequence earns it —
        /// typically whichever flag decides what the rest of them mean.
        public static func detail(
            key: FlagKey,
            title: String,
            symbol: String = "square.stack.3d.up"
        ) -> FlagCompanionTab {
            FlagCompanionTab(id: "detail.\(key.rawValue)", title: title, symbol: symbol) {
                AnyView(FlagDetailView(store: $0, key: key, title: title))
            }
        }

        /// Anything of your own, handed the same store the built-in tabs use.
        public static func custom<Content: View>(
            id: String,
            title: String,
            symbol: String,
            @ViewBuilder content: @escaping (FlagEditingStore) -> Content
        ) -> FlagCompanionTab {
            FlagCompanionTab(id: id, title: title, symbol: symbol) { AnyView(content($0)) }
        }
    }

    // MARK: - The default layout

    /// Renders a list of tabs, filled when selected and outlined otherwise.
    public struct FlagCompanionTabs: View {

        private let store: FlagEditingStore
        private let tabs: [FlagCompanionTab]

        @State private var selection: String

        public init(store: FlagEditingStore, tabs: [FlagCompanionTab] = [.overrides, .flags]) {
            // A tab's id is what the TabView switches on, so two sharing one means one of
            // them can never be shown — and `ForEach` has no identity to animate by
            // either. There is no correct rendering to fall back to, and listing
            // `.overrides` twice is an easy thing to do by accident.
            precondition(
                Self.duplicateID(in: tabs) == nil,
                """
                A companion cannot have two tabs with the id \
                '\(Self.duplicateID(in: tabs) ?? "")'. Give one of them a different id, \
                or drop it.
                """
            )

            self.store = store
            self.tabs = tabs
            self._selection = State(initialValue: tabs.first?.id ?? "")
        }

        /// The first id claimed by more than one tab, if any.
        static func duplicateID(in tabs: [FlagCompanionTab]) -> String? {
            var seen = Set<String>()
            for tab in tabs where seen.insert(tab.id).inserted == false {
                return tab.id
            }
            return nil
        }

        /// Whether there is nothing to render. Exposed so the failure is testable rather
        /// than something you notice by staring at a blank screen.
        var isEmptyOfTabs: Bool { tabs.isEmpty }

        public var body: some View {
            if isEmptyOfTabs {
                // A TabView with no tabs draws nothing at all, which is indistinguishable
                // from the app being broken. Say which it is.
                FlagCompanionUnavailableView(
                    title: "No tabs",
                    message: "This companion was given an empty tab list, so there is "
                        + "nothing to show. Pass at least one, or omit the argument for "
                        + "the default two."
                )
            } else {
                TabView(selection: $selection) {
                    ForEach(tabs) { tab in
                        tab.content(store)
                            .flagCompanionTab(
                                tab.title, symbol: tab.symbol, isSelected: selection == tab.id
                            )
                            .tag(tab.id)
                    }
                }
            }
        }
    }

    extension View {

        /// A tab item that fills its symbol when selected and outlines it otherwise.
        ///
        /// Two things this needs that are easy to get wrong. The symbol must ship a
        /// `.fill` variant — `slider.horizontal.3` and `dot.radiowaves.left.and.right`
        /// do not, so a selected tab drawn with them looks like every other one. And iOS
        /// fills tab bar glyphs for you, so the outline name alone changes nothing;
        /// `symbolVariants` has to be cleared on the label itself, not on the `TabView`.
        public func flagCompanionTab(
            _ title: String,
            symbol: String,
            isSelected: Bool
        ) -> some View {
            tabItem {
                Label(title, systemImage: isSelected ? symbol + ".fill" : symbol)
                    .environment(\.symbolVariants, .none)
            }
        }
    }

    // MARK: - Failure

    /// Why a companion has nothing to show, and what to do about it.
    struct FlagCompanionUnavailableView: View {

        var title: String = "No flags yet"
        let message: String
        var retry: (() -> Void)?

        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "flag.slash").font(.largeTitle)
                Text(title).font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let retry {
                    Button("Try again", action: retry)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Loading

    /// Opens the shared store, and says which of the two failures happened.
    ///
    /// Not private: the failure text is the only thing standing between someone and a
    /// blank screen, so it is worth testing directly.
    final class FlagCompanionLoader: ObservableObject {

        enum State {
            case loading
            case ready(FlagEditingStore)
            case failed(String)
        }

        @Published private(set) var state: State = .loading

        private let appGroup: String

        init(appGroup: String) {
            self.appGroup = appGroup
        }

        func load() {
            do {
                state = .ready(try FlagEditingStore(appGroup: appGroup))
            } catch {
                state = .failed(Self.message(for: appGroup))
            }
        }

        /// Both failures — a missing entitlement and a host that has never run — surface
        /// as the same throw, and telling someone only "could not load" leaves them with
        /// nowhere to go. Name both, in the order they are worth checking.
        static func message(for appGroup: String) -> String {
            """
            Run the host app at least once so it can publish its flags, and check that \
            both targets declare the \(appGroup) App Group in their entitlements.
            """
        }
    }

#endif
