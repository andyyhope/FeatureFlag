#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// An array, edited a row at a time.
    ///
    /// The JSON block this replaces was honest but unkind: a misplaced comma rejected the
    /// whole value, and nothing told you what an element was supposed to be. The schema
    /// carries the element type, so each row can have the control its type deserves —
    /// a toggle, a date picker, a number field — without the companion ever seeing the
    /// host's Swift types.
    ///
    /// Only arrays of scalars get this. An array of arrays has no row that reads well, so
    /// it stays JSON.
    public struct FlagArrayEditorView: View {

        @ObservedObject private var store: FlagEditingStore

        private let entry: FlagSchema.Entry
        private let element: FlagValueType

        public init(store: FlagEditingStore, entry: FlagSchema.Entry, element: FlagValueType) {
            self.store = store
            self.entry = entry
            self.element = element
        }

        private var elements: [FlagValueBox] {
            guard case let .array(values) = store.value(for: entry) else { return [] }
            return values
        }

        public var body: some View {
            List {
                Section {
                    ForEach(Array(elements.enumerated()), id: \.offset) { index, value in
                        FlagArrayElementRow(
                            value: value,
                            element: element,
                            onChange: { replace(at: index, with: $0) }
                        )
                    }
                    .onDelete { offsets in
                        var values = elements
                        values.remove(atOffsets: offsets)
                        write(values)
                    }
                    .onMove { source, destination in
                        var values = elements
                        values.move(fromOffsets: source, toOffset: destination)
                        write(values)
                    }

                    Button {
                        write(elements + [element.emptyBox])
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                } header: {
                    Text("\(elements.count) \(elements.count == 1 ? "item" : "items")")
                } footer: {
                    Text(
                        "Every element is a \(element.typeName). Removing them all leaves an "
                            + "empty array, which is a value like any other — reset the flag "
                            + "if you want the app's default back."
                    )
                }

                if store.isOverridden(entry) {
                    Section {
                        Button("Reset to the app's default", role: .destructive) {
                            try? store.reset(entry)
                        }
                    }
                }
            }
            .navigationTitle(entry.description)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { EditButton() }
            #endif
        }

        // MARK: - Writing

        private func replace(at index: Int, with value: FlagValueBox) {
            var values = elements
            guard values.indices.contains(index) else { return }
            values[index] = value
            write(values)
        }

        private func write(_ values: [FlagValueBox]) {
            try? store.setValue(.array(values), for: entry)
        }
    }

    // MARK: - One element

    /// The control an element's type deserves, rather than a fragment of JSON.
    struct FlagArrayElementRow: View {

        let value: FlagValueBox
        let element: FlagValueType
        let onChange: (FlagValueBox) -> Void

        var body: some View {
            switch element {
            case .bool:
                Toggle(
                    isOn: Binding(
                        get: { if case let .bool(flag) = value { return flag } else { return false } },
                        set: { onChange(.bool($0)) }
                    )
                ) {
                    Text(value.displayString).font(.body.monospaced())
                }

            case .date:
                DatePicker(
                    selection: Binding(
                        get: { if case let .date(date) = value { return date } else { return Date() } },
                        set: { onChange(.date($0)) }
                    )
                ) {
                    EmptyView()
                }
                .labelsHidden()

            default:
                // The same field the flag rows use, rather than a bare TextField: it
                // carries the border that marks where the editable region is, and it
                // refuses an edit that does not parse instead of guessing. Without it an
                // empty string element renders as a blank row with nothing to aim at.
                FlagTextField(
                    text: value.displayString,
                    keyboard: keyboard,
                    isMultiline: false
                ) { edited in
                    guard let box = FlagValueBox(displayString: edited, as: element) else {
                        return false
                    }
                    onChange(box)
                    return true
                }
            }
        }

        private var keyboard: TextInputKeyboard {
            switch element {
            case .int, .double, .float: return .numbersAndPunctuation
            case .url: return .URL
            default: return .default
            }
        }
    }

    // MARK: - A new element

    extension FlagValueType {

        /// What "Add" appends: the emptiest value of this type, so a new row is something
        /// to edit rather than something to interpret.
        var emptyBox: FlagValueBox {
            switch self {
            case .bool: return .bool(false)
            case .int: return .int(0)
            case .double: return .double(0)
            case .float: return .float(0)
            case .string: return .string("")
            case .data: return .data(Data())
            case .date: return .date(Date())
            case .url: return .url(URL(string: "https://example.com")!)
            case let .array(element): return .array([element.emptyBox])
            case .dictionary: return .dictionary([:])
            }
        }
    }

#endif
