// The editor is an iOS and macOS surface. watchOS has no Menu, TextEditor or
// bordered text field, and a flag-editing companion on a watch is not a real use case;
// tvOS has no text entry worth the name. The core FeatureFlag module supports every
// platform — this is only the UI.
#if os(iOS) || os(macOS)

import FeatureFlag
import SwiftUI

/// One flag, with the control its type calls for.
public struct FlagRowView: View {

    @ObservedObject private var store: FlagEditingStore
    private let entry: FlagSchema.Entry

    public init(store: FlagEditingStore, entry: FlagSchema.Entry) {
        self.store = store
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            switch entry.editorKind {
            case .toggle:
                Toggle(isOn: boolBinding) { Text(entry.description) }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)

            case let .picker(cases):
                Picker(entry.description, selection: pickerBinding) {
                    ForEach(cases, id: \.self) { value in
                        Text(value.displayString).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)

            case .date:
                DatePicker(entry.description, selection: dateBinding)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)

            case .integer, .decimal:
                textField(keyboard: .numbersAndPunctuation)

            case .url:
                textField(keyboard: .URL)

            case .text, .data, .json:
                textField(keyboard: .default)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description)
                    .font(.body)
                Text(entry.key.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if store.isOverridden(entry) {
                // The single most useful thing to see at a glance: what has been
                // changed away from what the app ships with.
                Text("Overridden")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())

                Button {
                    try? store.reset(entry)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to the app's default")
            }
        }
    }

    // MARK: - Editors

    @ViewBuilder
    private func textField(keyboard: TextInputKeyboard) -> some View {
        FlagTextField(
            text: store.value(for: entry).displayString,
            keyboard: keyboard,
            isMultiline: entry.editorKind == .json
        ) { edited in
            // Refuse an edit that does not parse rather than guessing at intent; the
            // field snaps back to the value still in effect.
            guard let box = FlagValueBox(displayString: edited, as: entry.valueType) else {
                return false
            }
            try? store.setValue(box, for: entry)
            return true
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { if case let .bool(value) = store.value(for: entry) { value } else { false } },
            set: { try? store.setValue(.bool($0), for: entry) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case let .date(value) = store.value(for: entry) { value } else { Date() } },
            set: { try? store.setValue(.date($0), for: entry) }
        )
    }

    private var pickerBinding: Binding<FlagValueBox> {
        Binding(
            get: { store.value(for: entry) },
            set: { try? store.setValue($0, for: entry) }
        )
    }
}

/// Keyboard hint, kept platform-neutral so the row compiles everywhere.
enum TextInputKeyboard {
    case `default`
    case numbersAndPunctuation
    case URL
}

/// A text field that commits only when the edited text parses.
struct FlagTextField: View {

    let text: String
    let keyboard: TextInputKeyboard
    let isMultiline: Bool
    let commit: (String) -> Bool

    @State private var draft: String = ""
    @State private var isRejected = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isMultiline {
                TextEditor(text: $draft)
                    .frame(minHeight: 60)
                    .font(.body.monospaced())
                    // Explicit, because the field beside it is trailing. JSON is
                    // structurally left-anchored — brackets, keys and indentation all
                    // read from the leading edge — so a longer payload becomes hard to
                    // scan when it is pushed right.
                    .multilineTextAlignment(.leading)
            } else {
                TextField("", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS) || os(tvOS)
                        .keyboardType(keyboard.uiKeyboardType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #endif
            }
        }
        .focused($isFocused)
        .overlay(alignment: .trailing) {
            if isRejected {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.trailing, 6)
                    .help("Not a valid value for this flag")
            }
        }
        .onAppear { draft = text }
        .onChange(of: text) { newValue in
            guard isFocused == false else { return }
            draft = newValue
        }
        .onChange(of: isFocused) { focused in
            guard focused == false else { return }
            isRejected = commit(draft) == false
            if isRejected { draft = text }
        }
        .onSubmit {
            isRejected = commit(draft) == false
            if isRejected { draft = text }
        }
    }
}

#if os(iOS) || os(tvOS)
    import UIKit

    extension TextInputKeyboard {
        var uiKeyboardType: UIKeyboardType {
            switch self {
            case .default: return .default
            case .numbersAndPunctuation: return .numbersAndPunctuation
            case .URL: return .URL
            }
        }
    }
#endif

#endif
