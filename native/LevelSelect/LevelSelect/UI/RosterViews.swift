import SwiftUI
import SwiftData

// MARK: - Targets

/// One item's details — a unit's fields and fate — for this playthrough.
struct ItemDetailsTarget: Identifiable, Hashable {
    var categoryID: String
    var itemID: String
    var id: String { "\(categoryID)/\(itemID)" }
}

/// A list's type and the fields its items carry.
struct ListSetupTarget: Identifiable, Hashable {
    var categoryID: String
    var id: String { categoryID }
}

// MARK: - The extra lines on an item row

/// What a roster or sequence row shows under the name: its status, its field
/// values, the party toggle, and "Next". Nothing at all for an ordinary item
/// with no status, which is most of them.
struct TrackerItemExtras: View {
    let category: TrackerCategoryDTO
    let values: TrackerFieldValues
    let isNext: Bool
    let hidden: Bool
    /// Ticked — for a roster, recruited. Only a unit you have can join the
    /// party, so the button waits for the tick rather than sitting on every row.
    var recruited: Bool = true
    let setParty: (Bool) -> Void

    var body: some View {
        if !hidden {
            if isNext {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
            }
            if let status = values.status {
                Label(statusText(status), systemImage: status.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(status == .inProgress ? AnyShapeStyle(LSTheme.accent)
                                     : AnyShapeStyle(.orange.opacity(0.9)))
            }
            let chips = fieldSummary
            let inParty = values.toggle(TrackerFieldDTO.partyID)
            let offerParty = category.partyField != nil && values.status != .fallen && (recruited || inParty)
            if !chips.isEmpty || offerParty {
                HStack(spacing: 6) {
                    if !chips.isEmpty {
                        Text(chips)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if offerParty {
                        Button {
                            setParty(!inParty)
                        } label: {
                            Label(inParty ? "In party" : "Add to party",
                                  systemImage: inParty ? "person.fill.checkmark" : "person.badge.plus")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(inParty ? LSTheme.accent.opacity(0.2) : Color.secondary.opacity(0.12),
                                            in: .capsule)
                                .foregroundStyle(inParty ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                        .lsTapTargetInline()
                        .accessibilityLabel(inParty ? "In party. Remove from party" : "Add to party")
                    }
                }
            }
        }
    }

    private func statusText(_ status: TrackerItemStatus) -> String {
        if status == .fallen, let place = values.text(TrackerFieldValues.fellInKey) {
            return "Fell in \(place)"
        }
        return status.label
    }

    /// "Sage · Lv 18 · Marth": the non-toggle fields with a value, in order.
    /// A number reads with its field's name, since "18" alone says nothing.
    private var fieldSummary: String {
        category.fields.compactMap { field -> String? in
            switch field.kind {
            case .toggle: return nil
            case .number: return values.text(field.id).map { "\(field.name) \($0)" }
            case .text, .choice: return values.text(field.id)
            case .multi:
                let picks = TrackerFieldDTO.picks(in: values.text(field.id))
                return picks.isEmpty ? nil : picks.joined(separator: " / ")
            }
        }
        .joined(separator: " · ")
    }
}

// MARK: - Item details

/// A unit's sheet: every field its list declares, and where it stands.
struct ItemDetailsSheet: View {
    @Bindable var game: Game
    let target: ItemDetailsTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var texts: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var status: TrackerItemStatus?
    @State private var fellIn = ""
    @State private var primed = false

    private var repo: Repository { Repository(context) }
    /// Where this item's answers are read. A shared list reads the record,
    /// which may not exist yet; writing makes it.
    private var playthrough: Playthrough? {
        category?.carried == true ? repo.existingCarriedPlaythrough(for: game)
            : repo.ensureDefaultPlaythrough(for: game)
    }

    private var category: TrackerCategoryDTO? {
        game.trackerSchema.flatMap { TrackerSchemaJSON.categories(from: $0.jsonData) }?
            .first { $0.id == target.categoryID }
    }
    private var item: TrackerItemDTO? { category?.items.first { $0.id == target.itemID } }

    /// What other units in the list already answered, for a choice with no
    /// options of its own: typing "Sage" once offers it for the next unit.
    private func earlierAnswers(_ field: TrackerFieldDTO) -> [String] {
        guard let category else { return [] }
        var seen = Set<String>()
        guard let playthrough else { return [] }
        return category.items.flatMap { item -> [String] in
            let text = repo.trackerState(playthrough, itemID: item.id)?.fieldValues.text(field.id)
            return field.kind == .multi ? TrackerFieldDTO.picks(in: text) : (text.map { [$0] } ?? [])
        }
        .filter { seen.insert($0).inserted }
        .sorted()
    }

    var body: some View {
        NavigationStack {
            LSForm {
                if let category {
                    if category.fields.isEmpty {
                        Section {
                            Text("This list doesn't record anything beyond its checkbox yet. Press and hold the list's name and choose List Type & Fields… to add class, level, party and the rest.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            ForEach(category.fields) { field in
                                fieldRow(field)
                            }
                        } footer: {
                            Text(category.carried
                                 ? "This list is remembered across playthroughs, so these answers are too."
                                 : "For this playthrough. A new playthrough starts every unit blank.")
                        }
                    }
                    Section {
                        Picker("Status", selection: $status) {
                            Text("None").tag(TrackerItemStatus?.none)
                            ForEach(statuses(for: category), id: \.self) { s in
                                Label(s.label, systemImage: s.systemImage).tag(TrackerItemStatus?.some(s))
                            }
                        }
                        if status == .fallen {
                            TextField("Where (Chapter 12, the final map…)", text: $fellIn)
                        }
                    } header: {
                        Text("Status")
                    } footer: {
                        Text(status == .fallen
                             ? "A fallen unit keeps its tick — you did recruit them — and leaves the party."
                             : "Failed and missed stay on the list and don't count as done.")
                    }
                }
            }
            .lsFormStyle()
            .navigationTitle(item?.name ?? "Details")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear(perform: prime)
        }
    }

    private func statuses(for category: TrackerCategoryDTO) -> [TrackerItemStatus] {
        category.isRoster ? [.fallen] + TrackerItemStatus.general : TrackerItemStatus.general
    }

    @ViewBuilder
    private func fieldRow(_ field: TrackerFieldDTO) -> some View {
        switch field.kind {
        case .toggle:
            Toggle(field.name, isOn: Binding(
                get: { toggles[field.id] ?? false },
                set: { toggles[field.id] = $0 }))
                .disabled(field.id == TrackerFieldDTO.partyID && status == .fallen)
        case .number:
            LabeledContent(field.name) {
                TextField("—", text: binding(field.id))
                    .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        case .text:
            LabeledContent(field.name) {
                TextField("—", text: binding(field.id))
                    .multilineTextAlignment(.trailing)
            }
        case .multi:
            let options = field.options.isEmpty ? earlierAnswers(field) : field.options
            if options.isEmpty {
                LabeledContent(field.name) {
                    TextField("Separate with commas", text: binding(field.id))
                        .multilineTextAlignment(.trailing)
                }
            } else {
                MultiPickRow(label: field.name,
                             options: options + TrackerFieldDTO.picks(in: texts[field.id]).filter { !options.contains($0) },
                             value: binding(field.id), max: field.max)
            }
        case .choice:
            let options = field.options.isEmpty ? earlierAnswers(field) : field.options
            LabeledContent(field.name) {
                HStack(spacing: 6) {
                    TextField("—", text: binding(field.id))
                        .multilineTextAlignment(.trailing)
                    if !options.isEmpty {
                        Menu {
                            ForEach(options, id: \.self) { option in
                                Button(option) { texts[field.id] = option }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .accessibilityLabel("Choose \(field.name)")
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { texts[id] ?? "" }, set: { texts[id] = $0 })
    }

    private func prime() {
        guard !primed else { return }
        primed = true
        let values = playthrough.flatMap { repo.trackerState($0, itemID: target.itemID) }?.fieldValues ?? .init()
        for field in category?.fields ?? [] {
            switch field.kind {
            case .toggle: toggles[field.id] = values.toggle(field.id)
            default: texts[field.id] = values.text(field.id) ?? ""
            }
        }
        status = values.status
        fellIn = values.text(TrackerFieldValues.fellInKey) ?? ""
    }

    /// Writes only what changed, so an untouched field keeps its own time and
    /// can't beat a newer edit from another device.
    private func save() {
        guard let category else { return }
        let pt = repo.statePlaythrough(for: game, category: category)
        let current = repo.trackerState(pt, itemID: target.itemID)?.fieldValues ?? .init()
        for field in category.fields {
            let new: TrackerFieldValues.Value?
            switch field.kind {
            case .toggle:
                let on = (toggles[field.id] ?? false) && !(field.id == TrackerFieldDTO.partyID && status == .fallen)
                new = on ? .toggle(true) : nil
            case .number:
                let raw = (texts[field.id] ?? "").trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ",", with: ".")
                new = raw.isEmpty ? nil : Double(raw).map { .number($0) } ?? .text(raw)
            case .text, .choice:
                let raw = (texts[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                new = raw.isEmpty ? nil : .text(raw)
            case .multi:
                var picks = TrackerFieldDTO.picks(in: texts[field.id])
                if let max = field.max, max > 0 { picks = Array(picks.prefix(max)) }
                new = picks.isEmpty ? nil : .text(picks.joined(separator: TrackerFieldDTO.multiSeparator))
            }
            if new != current.value(field.id) {
                repo.setTrackerField(pt, itemID: target.itemID, fieldID: field.id, value: new)
            }
        }
        let place = fellIn.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldPlace = current.text(TrackerFieldValues.fellInKey) ?? ""
        if status != current.status || (status == .fallen && place != oldPlace) {
            repo.setTrackerStatus(pt, itemID: target.itemID, status: status, fellIn: place)
        }
    }
}

// MARK: - List setup

/// A list's type — Checklist, Roster, In Order — its party size, and the
/// fields its items record.
struct ListSetupSheet: View {
    @Bindable var game: Game
    let target: ListSetupTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum ListType: String, CaseIterable, Identifiable {
        case checklist, roster, sequence
        var id: String { rawValue }
        var label: String {
            switch self {
            case .checklist: "Checklist"
            case .roster: "Roster"
            case .sequence: "In Order"
            }
        }
        var blurb: String {
            switch self {
            case .checklist: "Tick things off in any order."
            case .roster: "Characters: what each one is, who's in your party, and who fell."
            case .sequence: "Chapters or a questline, done in order, with the next one marked."
            }
        }
    }

    @State private var type: ListType = .checklist
    @State private var partySize = ""
    @State private var fields: [TrackerFieldDTO] = []
    @State private var progress: TrackerCategoryDTO.ProgressMode = .counts
    @State private var carried = false
    @State private var runField = ""
    @State private var winsOnly = true
    @State private var primed = false

    /// The game's run fields a list can tick from: the ones that name things.
    private var runFields: [RunFieldDTO] {
        guard let data = game.trackerSchema?.jsonData,
              let template = TrackerSchemaJSON.runTemplate(from: data) else { return [] }
        return template.fields.filter { !$0.isNumeric }
    }

    private var repo: Repository { Repository(context) }
    private var category: TrackerCategoryDTO? {
        game.trackerSchema.flatMap { TrackerSchemaJSON.categories(from: $0.jsonData) }?
            .first { $0.id == target.categoryID }
    }

    /// A start for a party RPG, each one editable after.
    static let rpgFields = TrackerFieldDTO.rpgDefaults()

    var body: some View {
        NavigationStack {
            LSForm {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ListType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(type.blurb)
                }

                Section {
                    Picker("Progress", selection: $progress) {
                        ForEach(TrackerCategoryDTO.ProgressMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Remembered across playthroughs", isOn: $carried)
                } header: {
                    Text("How it counts")
                } footer: {
                    Text(progressFooter)
                }

                if !runFields.isEmpty {
                    Section {
                        Picker("Tick from runs", selection: $runField) {
                            Text("Off").tag("")
                            ForEach(runFields) { Text($0.label).tag($0.id) }
                        }
                        if !runField.isEmpty {
                            Toggle("Only won runs", isOn: $winsOnly)
                        }
                    } header: {
                        Text("Runs")
                    } footer: {
                        Text(runField.isEmpty
                             ? "An item can tick itself when a run uses it — win with every weapon."
                             : "An item ticks when a finished run\(winsOnly ? " you won" : "") has it as its \(runFields.first { $0.id == runField }?.label ?? "value"). Your past runs count too.")
                    }
                }

                if type == .roster {
                    Section {
                        LabeledContent("Party size") {
                            TextField("No limit", text: $partySize)
                                .multilineTextAlignment(.trailing)
                                #if !os(macOS)
                                .keyboardType(.numberPad)
                                #endif
                        }
                    } footer: {
                        Text("Shown beside the party count — \"13 of 14\". It's a reminder, not a rule.")
                    }
                }

                Section {
                    ForEach($fields) { $field in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Name", text: $field.name)
                                .font(.body.weight(.medium))
                                .disabled(field.id == TrackerFieldDTO.partyID)
                            Picker("Kind", selection: $field.kind) {
                                ForEach(TrackerFieldDTO.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .disabled(field.id == TrackerFieldDTO.partyID)
                            if field.kind.hasOptions {
                                TextField("Options, separated by commas (optional)", text: Binding(
                                    get: { field.options.joined(separator: ", ") },
                                    set: { field.options = $0.split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty } }))
                                    .font(.caption)
                            }
                            if field.kind == .multi {
                                TextField("How many at once (optional)", text: Binding(
                                    get: { field.max.map(String.init) ?? "" },
                                    set: { field.max = Int($0.trimmingCharacters(in: .whitespaces)) }))
                                    .font(.caption)
                                    #if !os(macOS)
                                    .keyboardType(.numberPad)
                                    #endif
                            }
                        }
                    }
                    .onDelete { fields.remove(atOffsets: $0) }
                    .onMove { fields.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        Button("Text") { addField(.text) }
                        Button("Number") { addField(.number) }
                        Button("Choice") { addField(.choice) }
                        Button("Several choices") { addField(.multi) }
                        Button("On / off") { addField(.toggle) }
                        if !fields.contains(where: { $0.id == TrackerFieldDTO.partyID }) {
                            Divider()
                            Button("In party") {
                                fields.append(.init(id: TrackerFieldDTO.partyID, name: "In party", kind: .toggle))
                            }
                        }
                    } label: {
                        Label("Add a Field", systemImage: "plus")
                    }
                    if fields.isEmpty, type == .roster {
                        Button {
                            fields = Self.rpgFields
                        } label: {
                            Label("Start with Class, Level, Weapon and Party", systemImage: "sparkles")
                        }
                    }
                } header: {
                    Text("What each item records")
                } footer: {
                    Text("Values are per playthrough. Removing a field hides it; its answers come back if you add it again with the same name.")
                }
            }
            .lsFormStyle()
            .navigationTitle(category?.name ?? "List")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
            }
            .onAppear(perform: prime)
        }
    }

    private func addField(_ kind: TrackerFieldDTO.Kind) {
        fields.append(.init(id: "f-\(UUID().uuidString.prefix(6).lowercased())",
                            name: kind == .number ? "Level" : "", kind: kind))
    }

    private func prime() {
        guard !primed, let category else { return }
        primed = true
        type = category.isRoster ? .roster : category.isSequence ? .sequence : .checklist
        partySize = category.partySize.map(String.init) ?? ""
        fields = category.fields
        progress = category.progress
        carried = category.carried
        runField = category.fromRuns?.field ?? ""
        winsOnly = category.fromRuns?.winsOnly ?? true
    }

    private var progressFooter: String {
        var parts: [String] = []
        switch progress {
        case .counts: parts.append("Each item counts toward the game's percentage when it's ticked.")
        case .excluded: parts.append("This list is left out of the game's percentage.")
        case .partial: parts.append("Counters and ranks count for how far along they are — 450 of 900 is half an item.")
        }
        if carried {
            parts.append("Ticks here belong to the game, not one playthrough: endings seen, unlocks that carry over. They show on every playthrough.")
        }
        return parts.joined(separator: " ")
    }

    private func save() {
        guard let category else { return }
        // A field's id follows its name the first time it's saved, so answers
        // survive removing and re-adding it by the same name.
        var used = Set<String>()
        let cleaned: [TrackerFieldDTO] = fields.compactMap { field in
            let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var out = field
            out.name = name
            if out.id.hasPrefix("f-") {
                let slug = TrackerMerge.matchKey(name).replacingOccurrences(of: " ", with: "-")
                if !slug.isEmpty, !slug.hasPrefix("_") { out.id = slug }
            }
            guard used.insert(out.id).inserted else { return nil }
            return out
        }
        let kind: String? = type == .checklist ? nil : type.rawValue
        let size = type == .roster ? Int(partySize.trimmingCharacters(in: .whitespaces)) : nil
        if kind != category.kind || size != category.partySize {
            repo.setListKind(game, categoryID: category.id, kind: kind, partySize: size)
        }
        if cleaned != category.fields {
            repo.setListFields(game, categoryID: category.id, fields: cleaned)
        }
        let rule = runField.isEmpty ? nil : TrackerCategoryDTO.RunTick(field: runField, winsOnly: winsOnly)
        if progress != category.progress || carried != category.carried || rule != category.fromRuns {
            repo.setListRules(game, categoryID: category.id, progress: progress,
                              carried: carried, fromRuns: rule)
        }
    }
}

// MARK: - Focus

/// Which lists this playthrough is chasing — Any% or 112%. The rest fold
/// away, keep their ticks, and leave the percentage.
struct TrackerFocusSheet: View {
    @Bindable var game: Game
    /// Asked right after a playthrough is made: "What's this run for?"
    var newRun = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<String> = []
    @State private var primed = false

    private var repo: Repository { Repository(context) }
    private var categories: [TrackerCategoryDTO] {
        repo.trackerCategories(for: game).filter { !$0.pending }
    }

    var body: some View {
        NavigationStack {
            LSForm {
                if newRun {
                    Section {
                        NavigationLink {
                            TrackerShapeView(game: game, focusing: game.activePlaythrough) {
                                save()
                                dismiss()
                            }
                        } label: {
                            Label(categories.isEmpty ? "Plan a Tracker for This Run…" : "Plan New Lists for This Run…",
                                  systemImage: "list.bullet.rectangle.portrait")
                        }
                    } footer: {
                        Text("New lists join the tracker and become what this run counts.")
                    }
                }
                if !categories.isEmpty {
                Section {
                    ForEach(categories) { category in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(category.id) },
                            set: { on in
                                if on { chosen.insert(category.id) } else { chosen.remove(category.id) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(newRun ? "Lists this run chases" : (game.activePlaythrough?.name ?? "This playthrough"))
                } footer: {
                    Text(chosen.isEmpty
                         ? "Nothing chosen means every list is in focus."
                         : "Only these count toward this playthrough's progress. The others fold into one row below the tracker, and their ticks stay.")
                }
                }
                if !chosen.isEmpty {
                    Section {
                        Button("Focus on Everything") { chosen = [] }
                    }
                }
            }
            .lsFormStyle()
            .navigationTitle(newRun ? "What's This Run For?" : "Focus")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(newRun ? "Skip" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(newRun ? "Done" : "Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !primed else { return }
                primed = true
                chosen = repo.focus(of: game.activePlaythrough) ?? []
            }
        }
    }

    private func save() {
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let ids = chosen.count == categories.count ? [] : chosen
        if ids != (repo.focus(of: pt) ?? []) { repo.setFocus(ids, on: pt) }
    }
}
