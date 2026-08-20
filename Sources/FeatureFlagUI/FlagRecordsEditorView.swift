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
                FlagRecordList(
                    fields: fields,
                    records: store.records(for: entry),
                    unreadableText: store.value(for: entry).displayString,
                    // Every change starts from what is stored right now rather than from
                    // the array this screen was built with. A record's own screen is
                    // pushed on top of this list and lives as long as you are editing it,
                    // so writing back a captured copy would undo anything that happened
                    // in between — silently, and to records you never opened.
                    onChange: { change in
                        guard var current = store.records(for: entry) else { return }
                        change(&current)
                        try? store.setRecords(current, for: entry)
                    },
                    emptyRecord: { entry.emptyRecord(alongside: $0) }
                )

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
    }

    // MARK: - The list itself

    /// The sections a list of records is made of, independent of where the list lives.
    ///
    /// A flag's list comes from the store; a nested list comes from one field of one
    /// record. They are the same screen, so they are the same view — the difference is
    /// only how a change gets written back.
    struct FlagRecordList: View {

        let fields: [FlagRecordField]
        /// `nil` when the stored text is not a list of records at all.
        let records: [[String: FlagValueBox]]?
        let unreadableText: String
        let onChange: ((inout [[String: FlagValueBox]]) -> Void) -> Void
        let emptyRecord: ([[String: FlagValueBox]]) -> [String: FlagValueBox]

        var body: some View {
            if let records {
                Section {
                    ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                        NavigationLink {
                            FlagRecordEditorView(
                                title: summary(of: record),
                                fields: fields,
                                record: record,
                                keysInUse: Set(
                                    records.enumerated()
                                        .filter { $0.offset != index }
                                        .compactMap { pair in
                                            fields.first(where: \.isKey)
                                                .flatMap { pair.element[$0.name] }
                                        }
                                ),
                                onChange: { edited in
                                    onChange { current in
                                        guard current.indices.contains(index) else { return }
                                        current[index] = edited
                                    }
                                }
                            )
                        } label: {
                            row(record)
                        }
                        .swipeActions(edge: .leading) {
                            // Leading, because the destructive one owns the trailing edge
                            // and duplicating a record by mistake should never be one slip
                            // away from deleting it.
                            Button {
                                onChange { current in
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
                        onChange { $0.remove(atOffsets: offsets) }
                    }
                    .onMove { source, destination in
                        onChange { $0.move(fromOffsets: source, toOffset: destination) }
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

                // Its own section rather than the last row of the list. A button sharing
                // a section with navigation rows takes the tap and then hands it on to
                // the row that lands where it was, so adding a record also opened it.
                Section {
                    Button {
                        onChange { $0.append(emptyRecord($0)) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            } else {
                Section {
                    Text(unreadableReason)
                    Text(unreadableText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } footer: {
                    // Said plainly because the app is already ignoring this value, and an
                    // editor that quietly showed an empty list would invite you to add a
                    // record and wonder why nothing changed.
                    Text(
                        "The app cannot read it either, so it is using its default. Reset "
                            + "the flag to edit it here."
                    )
                }
            }
        }

        /// Why the stored text cannot be read, which is not always the same answer.
        ///
        /// A duplicate key is a list of records — a perfectly well-formed one — that
        /// breaks a different rule, and saying "this is not a list of records" would
        /// send someone looking for a syntax problem that is not there.
        private var unreadableReason: String {
            if let duplicate = FlagValueBox.string(unreadableText)
                .duplicateRecordKey(matching: fields),
                let key = fields.first(where: \.isKey)?.name
            {
                return """
                    Two records share the same \(key), \(duplicate.displayString) — it is \
                    what tells one record from another, so they cannot.
                    """
            }
            return "This value is not a list of records."
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
            // The key when there is one — it is the field that says which record this
            // is, which is precisely what a row title is for. Otherwise the first
            // declared field, which is a guess but a consistent one.
            let titleField = fields.first(where: \.isKey) ?? fields.first
            guard let titleField, let box = record[titleField.name] else {
                return "Record"
            }
            let text = box.displayString
            return text.isEmpty ? "Untitled" : text
        }

        /// Everything but the first field, which the summary already showed.
        private func detail(of record: [String: FlagValueBox]) -> String {
            let titleField = fields.first(where: \.isKey) ?? fields.first
            return fields
                .filter { $0.name != titleField?.name }
                .map { "\($0.name): \(summary(of: $0, in: record))" }
                .joined(separator: "  ")
        }

        /// A nested list reads as "2 targets" rather than as its escaped JSON, which is
        /// unreadable at row width and tells you nothing a count does not.
        private func summary(of field: FlagRecordField, in record: [String: FlagValueBox]) -> String {
            guard let box = record[field.name] else { return "—" }
            guard let nested = field.fields else { return box.displayString }
            let count = box.recordValues(matching: nested)?.count ?? 0
            return "\(count)"
        }
    }

    // MARK: - One record

    /// One record on a screen of its own: a row per field, each with the control its
    /// type calls for.
    struct FlagRecordEditorView: View {

        let title: String
        let fields: [FlagRecordField]
        let record: [String: FlagValueBox]
        /// The key values the other records already have, so this screen can refuse an
        /// edit that would collide instead of writing one the host will not read.
        var keysInUse: Set<FlagValueBox> = []
        let onChange: ([String: FlagValueBox]) -> Void

        var body: some View {
            Form {
                Section {
                    ForEach(fields, id: \.name) { field in
                        FlagRecordFieldRow(
                            field: field,
                            value: record[field.name] ?? field.emptyBox,
                            unavailable: field.isKey ? keysInUse : [],
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
        /// Values this field may not take, because another record already has them.
        var unavailable: Set<FlagValueBox> = []
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
            if let nested = field.fields {
                // A list inside a record is the same screen one level down, rather than
                // the escaped JSON it is stored as — which is what a text field would
                // have shown, and which nobody can edit by hand without counting
                // backslashes.
                NavigationLink {
                    List {
                        FlagRecordList(
                            fields: nested,
                            records: value.recordValues(matching: nested),
                            unreadableText: value.displayString,
                            onChange: { change in
                                var current = value.recordValues(matching: nested) ?? []
                                change(&current)
                                onChange(.records(current))
                            },
                            emptyRecord: { existing in
                                var record = Dictionary(
                                    uniqueKeysWithValues: nested.map { ($0.name, $0.emptyBox) }
                                )
                                guard let key = nested.first(where: \.isKey) else { return record }
                                let taken = Set(existing.compactMap { $0[key.name] })
                                if taken.contains(record[key.name] ?? key.emptyBox) {
                                    for suffix in 2...(taken.count + 2) {
                                        guard let candidate = key.emptyBox.appendingSuffix(suffix)
                                        else { break }
                                        if taken.contains(candidate) == false {
                                            record[key.name] = candidate
                                            break
                                        }
                                    }
                                }
                                return record
                            }
                        )
                    }
                    .navigationTitle(field.name)
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { EditButton() }
                    #endif
                } label: {
                    Text(nestedSummary(nested))
                        .foregroundStyle(.secondary)
                }
            } else if let cases = field.cases, cases.isEmpty == false {
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
                        // Refused the same way an unparseable edit is: the field snaps
                        // back to what is still in effect and marks itself, rather than
                        // writing a list the host would refuse to read.
                        guard let box = FlagValueBox(displayString: edited, as: field.type),
                            unavailable.contains(box) == false
                        else { return false }
                        onChange(box)
                        return true
                    }
                }
            }
        }

        /// "2 records", or that the stored text is not any — the same thing the flag row
        /// says, one level down.
        private func nestedSummary(_ nested: [FlagRecordField]) -> String {
            guard let records = value.recordValues(matching: nested) else {
                return "Unreadable"
            }
            return "\(records.count) record\(records.count == 1 ? "" : "s")"
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
        ///
        /// Throws rather than writing a list with a duplicate key. The host refuses one,
        /// so writing it would leave the flag reading its default with the editor still
        /// showing what you typed.
        public func setRecords(
            _ records: [[String: FlagValueBox]],
            for entry: FlagSchema.Entry
        ) throws {
            if let shape = entry.recordShape,
                let duplicate = FlagValueBox.duplicateKey(in: records, matching: shape)
            {
                throw FlagRecordEditingError.duplicateKey(
                    field: shape.first(where: \.isKey)?.name ?? "key",
                    value: duplicate
                )
            }
            try setValue(.records(records), for: entry)
        }
    }

    /// A change the editor will not make.
    public enum FlagRecordEditingError: Error, CustomStringConvertible, LocalizedError {

        /// Two records would share the key that tells them apart.
        case duplicateKey(field: String, value: FlagValueBox)

        public var description: String {
            switch self {
            case let .duplicateKey(field, value):
                return """
                    Another record already has that \(field). It is what tells one record \
                    from another, so two cannot share it.
                    """
            }
        }

        public var errorDescription: String? { description }
    }

    extension FlagValueBox {

        /// This value with a counter appended, for generating a distinct placeholder.
        ///
        /// Only the two types a counter means anything for. Anything else keeps its
        /// empty value, and the editor shows the collision rather than inventing data.
        func appendingSuffix(_ suffix: Int) -> FlagValueBox? {
            switch self {
            case let .string(value):
                return .string(value.isEmpty ? "\(suffix)" : "\(value) \(suffix)")
            case let .int(value):
                return .int(value + suffix - 1)
            default:
                return nil
            }
        }
    }

    extension FlagRecordField {

        /// What a new record starts this field at.
        ///
        /// The value the field was declared with, when it has one — the author already
        /// said what a sensible starting point is, and repeating it here would be a
        /// second opinion. Failing that, an enum field starts on a real case rather
        /// than an empty string, which is not a value of its type and would have the
        /// host reject the record, and with it the whole list.
        var emptyBox: FlagValueBox {
            defaultValue ?? cases?.first ?? type.emptyBox
        }
    }

    extension FlagSchema.Entry {

        /// A record with every field at its emptiest usable value, which is what "Add"
        /// appends: something to edit rather than something to interpret.
        var emptyRecord: [String: FlagValueBox] {
            emptyRecord(alongside: [])
        }

        /// The same, made distinct from the records it is joining.
        ///
        /// Without this, pressing "Add" twice writes two records sharing an empty key,
        /// which the host refuses — so the whole flag would fall back to its default on
        /// the second press, with nothing on screen to say why.
        func emptyRecord(
            alongside existing: [[String: FlagValueBox]]
        ) -> [String: FlagValueBox] {
            guard let shape = recordShape else { return [:] }
            var record = Dictionary(uniqueKeysWithValues: shape.map { ($0.name, $0.emptyBox) })

            guard let key = shape.first(where: \.isKey) else { return record }
            let taken = Set(existing.compactMap { $0[key.name] })
            guard taken.contains(record[key.name] ?? key.emptyBox) else { return record }

            // Counting up from what the field would have held anyway keeps the
            // generated value recognisable as a placeholder rather than as data.
            for suffix in 2...(taken.count + 2) {
                guard let candidate = key.emptyBox.appendingSuffix(suffix) else { break }
                if taken.contains(candidate) == false {
                    record[key.name] = candidate
                    return record
                }
            }
            return record
        }
    }

#endif
