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

        /// The zero-configuration companion: overrides, then the whole flag tree.
        public init(appGroup: String) {
            self.init(appGroup: appGroup) { store in
                FlagCompanionTabs(store: store)
            }
        }
    }

    // MARK: - The default layout

    /// The two tabs every companion wants: what has changed, and what can change.
    public struct FlagCompanionTabs: View {

        private enum Tab: Hashable {
            case overrides, flags
        }

        private let store: FlagEditingStore
        @State private var selection: Tab = .overrides

        public init(store: FlagEditingStore) {
            self.store = store
        }

        public var body: some View {
            TabView(selection: $selection) {
                FlagOverridesView(store: store)
                    .flagCompanionTab(
                        "Overrides", symbol: "dial.medium", isSelected: selection == .overrides
                    )
                    .tag(Tab.overrides)

                FlagBrowserView(store: store)
                    .flagCompanionTab(
                        "Flags", symbol: "flag", isSelected: selection == .flags
                    )
                    .tag(Tab.flags)
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

        let message: String
        let retry: () -> Void

        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "flag.slash").font(.largeTitle)
                Text("No flags yet").font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again", action: retry)
                    .padding(.top, 4)
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
