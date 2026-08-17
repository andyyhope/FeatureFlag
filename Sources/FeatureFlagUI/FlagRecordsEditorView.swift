#if os(iOS) || os(macOS)

    import FeatureFlag
    import SwiftUI

    /// A list of records, edited a record at a time.
    ///
    /// The companion has the shape and never the host's Swift types, so a record here is
    /// a dictionary of boxes keyed by field name. That is enough to lay out a row per
    /// record, push a screen per record, and write back something the host will read as
    /// the type it declared.
    public struct FlagRecordsEditorView: View {

        @ObservedObject private var store: FlagEditingStore

        private let entry: FlagSchema.Entry
        private let fields: [FlagRecordField]

        public init(store: FlagEditingStore, entry: FlagSchema.Entry, fields: [FlagRecordField]) {
            self.store = store
            self.entry = entry
            self.fields = fields
        }

        public var body: some View {
            List {
                if let records = store.records(for: entry) {
                    recordSection(records)
                } else {
                    unreadableSection
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

        // MARK: - The list

        @ViewBuilder
        private func recordSection(_ records: [[String: FlagValueBox]]) -> some View {
            Section {
                ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                    NavigationLink {
                        FlagRecordEditorView(
                            title: summary(of: record),
                            fields: fields,
                            record: record,
                            onChange: { edited in
                                mutate { current in
                                    guard current.indices.contains(index) else { return }
                                    current[index] = edited
                                }
                            }
                        )
                    } label: {
                        row(record)
                    }
                    .swipeActions(edge: .leading) {
                        // Leading, because the destructive one owns the trailing edge and
                        // duplicating a record by mistake should never be one slip away
                        // from deleting it.
                        Button {
                            mutate { current in
                                guard current.indices.contains(index) else { return }
                                current.insert(current[index], at: index + 1)
                            }
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.accentColor)
                    }
                }
                .onDelete { offsets in
                    mutate { $0.remove(atOffsets: offsets) }
                }
                .onMove { source, destination in
                    mutate { $0.move(fromOffsets: source, toOffset: destination) }
                }
            } header: {
                Text("\(records.count) \(records.count == 1 ? "record" : "records")")
            } footer: {
                Text(
                    "Each record has \(fields.count) "
                        + "\(fields.count == 1 ? "field" : "fields"): "
                        + fields.map(\.name).joined(separator: ", ") + "."
                )
            }

            // Its own section rather than the last row of the list. A button sharing a
            // section with navigation rows takes the tap and then hands it on to the row
            // that lands where it was, so adding a record also opened it.
            Section {
                Button {
                    mutate { $0.append(entry.emptyRecord) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }

        /// One row: what the record is, and a taste of the rest of it.
        private func row(_ record: [String: FlagValueBox]) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(of: record))
                Text(detail(of: record))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Tail, not middle: middle truncation cuts inside whichever field
                    // happens to sit in the centre, and "enabled:…ue" is worse than
                    // showing two fields whole and stopping.
                    .truncationMode(.tail)
            }
        }

        /// The first field that reads like a name, because a row headed "record 3" tells
        /// you nothing you could not have counted.
        private func summary(of record: [String: FlagValueBox]) -> String {
            guard let first = fields.first, let box = record[first.name] else {
                return "Record"
            }
            let text = box.displayString
            return text.isEmpty ? "Untitled" : text
        }

        /// Everything but the first field, which the summary already showed.
        private func detail(of record: [String: FlagValueBox]) -> String {
            fields
                .dropFirst()
                .map { "\($0.name): \(record[$0.name]?.displayString ?? "—")" }
                .joined(separator: "  ")
        }

        // MARK: - Nothing readable

        private var unreadableSection: some View {
            Section {
                Text("This value is not a list of records.")
                Text(store.value(for: entry).displayString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } footer: {
                // Said plainly because the app is already ignoring this value, and an
                // editor that quietly showed an empty list would invite you to add a
                // record and wonder why nothing changed.
                Text(
                    "The app cannot read it either, so it is using its default. Reset the "
                        + "flag to edit it here."
                )
            }
        }

        // MARK: - Writing

        /// Every change goes through here, and every change starts from what is stored
        /// right now rather than from the array this screen was built with.
        ///
        /// A record's own screen is pushed on top of this list and lives as long as you
        /// are editing it, so writing back a captured copy would undo anything that
        /// happened to the list in between — silently, and to records you never opened.
        private func mutate(_ change: (inout [[String: FlagValueBox]]) -> Void) {
            guard var current = store.records(for: entry) else { return }
            change(&current)
            try? store.setRecords(current, for: entry)
        }
    }

    // MARK: - One record

    /// One record on a screen of its own: a row per field, each with the control its
    /// type calls for.
    struct FlagRecordEditorView: View {

        let title: String
        let fields: [FlagRecordField]
        let record: [String: FlagValueBox]
        let onChange: ([String: FlagValueBox]) -> Void

        var body: some View {
            Form {
                Section {
                    ForEach(fields, id: \.name) { field in
                        FlagRecordFieldRow(
                            field: field,
                            value: record[field.name] ?? field.emptyBox,
                            onChange: { box in
                                var updated = record
                                updated[field.name] = box
                                onChange(updated)
                            }
                        )
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// One field of one record.
    struct FlagRecordFieldRow: View {

        let field: FlagRecordField
        let value: FlagValueBox
        let onChange: (FlagValueBox) -> Void

        /// The field's name above, its value below, the way the flag rows read. Sharing
        /// a line means the value gets whatever width the name leaves it, which is least
        /// where it is needed most — a long URL beside a long field name.
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.name)
                    Text(field.type.typeName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                control
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)
        }

        @ViewBuilder
        private var control: some View {
            if let cases = field.cases, cases.isEmpty == false {
                Picker(field.name, selection: binding) {
                    ForEach(cases, id: \.self) { option in
                        Text(option.displayString).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } else {
                switch field.type {
                case .bool:
                    Toggle("", isOn: boolBinding).labelsHidden()

                case .date:
                    DatePicker("", selection: dateBinding).labelsHidden()

                default:
                    FlagTextField(
                        text: value.displayString,
                        keyboard: keyboard,
                        isMultiline: false
                    ) { edited in
                        guard let box = FlagValueBox(displayString: edited, as: field.type) else {
                            return false
                        }
                        onChange(box)
                        return true
                    }
                }
            }
        }

        private var keyboard: TextInputKeyboard {
            switch field.type {
            case .int, .double, .float: return .numbersAndPunctuation
            case .url: return .URL
            default: return .default
            }
        }

        private var binding: Binding<FlagValueBox> {
            Binding(get: { value }, set: onChange)
        }

        private var boolBinding: Binding<Bool> {
            Binding(
                get: { if case let .bool(flag) = value { flag } else { false } },
                set: { onChange(.bool($0)) }
            )
        }

        private var dateBinding: Binding<Date> {
            Binding(
                get: { if case let .date(date) = value { date } else { Date() } },
                set: { onChange(.date($0)) }
            )
        }
    }

    // MARK: - Reading and writing records

    extension FlagEditingStore {

        /// The records stored for a record flag, or `nil` when the stored text is not a
        /// list the host could read either.
        public func records(for entry: FlagSchema.Entry) -> [[String: FlagValueBox]]? {
            guard let shape = entry.recordShape else { return nil }
            return value(for: entry).recordValues(matching: shape)
        }

        /// Writes records back as the text the host reads them from.
        public func setRecords(
            _ records: [[String: FlagValueBox]],
            for entry: FlagSchema.Entry
        ) throws {
            try setValue(.records(records), for: entry)
        }
    }

    extension FlagRecordField {

        /// What a new record starts this field at.
        ///
        /// An enum field starts on a real case rather than an empty string. Anything
        /// else is not a value of its type, so the host would reject the record — and
        /// with it the whole list — the moment it read it.
        var emptyBox: FlagValueBox {
            cases?.first ?? type.emptyBox
        }
    }

    extension FlagSchema.Entry {

        /// A record with every field at its emptiest usable value, which is what "Add"
        /// appends: something to edit rather than something to interpret.
        var emptyRecord: [String: FlagValueBox] {
            guard let shape = recordShape else { return [:] }
            return Dictionary(uniqueKeysWithValues: shape.map { ($0.name, $0.emptyBox) })
        }
    }

#endif
