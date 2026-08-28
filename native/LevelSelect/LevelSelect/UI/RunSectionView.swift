import SwiftUI
import SwiftData

/// Run tracker (roguelikes / Hades): start a live run with a loadout, end it
/// with an outcome, or log one after the fact. History + win-rate at a glance.
/// Runs are per-playthrough, like everything else.
struct RunSectionView: View {
    let game: Game
    let template: RunTemplateDTO
    @Environment(\.modelContext) private var context

    @State private var startingRun = false
    @State private var loggingRun = false
    @State private var endingRun: Run?
    @State private var showAnalytics = false
    @State private var historyFilter: HistoryFilter = .all

    enum HistoryFilter: String, CaseIterable {
        case all = "All", wins = "Wins", losses = "Losses"
    }

    private var repo: Repository { Repository(context) }
    private var playthrough: Playthrough? { game.activePlaythrough }
    private var runs: [Run] { playthrough?.liveRuns ?? [] }
    private var finished: [Run] { runs.filter { $0.outcome != .inProgress } }

    /// The tracker's categories back the run pickers (keepsakes come from the
    /// Keepsakes category, not a copied list) — same source the tracker
    /// section renders.
    private var categories: [TrackerCategoryDTO] {
        game.trackerSchema.map { TrackerSchemaJSON.categories(from: $0.jsonData) } ?? []
    }

    /// Items with any recorded progress, for `onlyUnlocked` pickers. Checked,
    /// ranked or counted all count — a keepsake at rank 2 is unlocked.
    private var progressedIDs: Set<String> {
        Set((playthrough?.trackerStates ?? [])
            .filter { $0.deletedAt == nil && ($0.completed || ($0.rank ?? 0) > 0 || ($0.count ?? 0) > 0) }
            .map(\.itemID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsRow

            if let active = playthrough?.activeRun {
                activeRunView(active)
            } else {
                // A run is one attempt; a session is time at the controls.
                // They're independent — you might play for an hour and log
                // four runs, or start a run without the timer going — so the
                // wording says which is which rather than leaving two similar
                // buttons to be told apart by icon.
                Text("A run is one attempt. Timing your play is separate.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack {
                    Button {
                        startingRun = true
                    } label: {
                        Label("Start Run", systemImage: "flag.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        loggingRun = true
                    } label: {
                        Label("Log", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if finished.count >= 3 {
                analytics
            }

            if !runs.isEmpty {
                history
            }
        }
        .sheet(isPresented: $startingRun) {
            RunFieldsSheet(template: template, categories: categories,
                           progressed: progressedIDs,
                           title: "Start Run", confirm: "Start") { fields in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.startRun(on: pt, fields: fields)
            }
        }
        .sheet(isPresented: $loggingRun) {
            LogRunSheet(template: template, categories: categories,
                        progressed: progressedIDs) { fields, outcome, started, duration, notes in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logRun(on: pt, fields: fields, outcome: outcome,
                            started: started, duration: duration, notes: notes)
            }
        }
        .sheet(item: $endingRun) { run in
            EndRunSheet(template: template, categories: categories,
                        progressed: progressedIDs, run: run) { outcome, notes, endFields in
                repo.endRun(run, outcome: outcome, notes: notes, extraFields: endFields)
            }
        }
    }

    // MARK: Pieces

    private var statsRow: some View {
        let finished = runs.filter { $0.outcome != .inProgress }
        let wins = finished.filter { $0.outcome == .success }.count
        return HStack {
            Text("\(finished.count) runs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if !finished.isEmpty {
                Text("\(wins) wins · \(Int((Double(wins) / Double(finished.count) * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(wins > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            // Turning run logging off was buried in the game's ⋯ menu, three
            // rows below things that had nothing to do with runs. It belongs
            // here, where the runs are and where the wording can promise that
            // they survive it.
            Menu {
                Button {
                    repo.setRunTracking(false, for: game)
                } label: {
                    Label("Turn Off Run Logging", systemImage: "flag.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
            }
            .accessibilityLabel("Run actions")
        }
    }

    private func activeRunView(_ run: Run) -> some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.clock(ctx.date.timeIntervalSince(run.startedAt)))
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            if !run.fieldsDict.isEmpty {
                Text(summary(run))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                endingRun = run
            } label: {
                Label("End Run", systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Win rate by loadout — the web app's AnalyticsSection, generalised.
    /// Collapsed by default like the rest of the page's secondary content;
    /// hidden entirely under three finished runs, where every percentage
    /// would be noise.
    private var analytics: some View {
        let stats = RunFieldSupport.stats(
            fields: template.fields,
            runs: finished.map { ($0.fieldsDict, $0.outcome == .success) })
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { showAnalytics.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Analytics")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showAnalytics ? 90 : 0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showAnalytics {
                if stats.isEmpty {
                    Text("Runs need a loadout picked from the lists for there to be anything to compare.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(stats) { fieldStats in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fieldStats.field.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            ForEach(fieldStats.rows.prefix(6)) { row in
                                HStack {
                                    Text(row.value)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    // The fraction always shows; the percent
                                    // only from three uses — "100%" alone and
                                    // "1/1" say very different things.
                                    Text(row.total >= 3
                                         ? "\(row.wins)/\(row.total) · \(Int((row.winRate * 100).rounded()))%"
                                         : "\(row.wins)/\(row.total)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(row.wins > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var filteredHistory: [Run] {
        switch historyFilter {
        case .all: finished
        case .wins: finished.filter { $0.outcome == .success }
        case .losses: finished.filter { $0.outcome == .failure }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if finished.count >= 6 {
                    Picker("Filter", selection: $historyFilter) {
                        ForEach(HistoryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 190)
                    .labelsHidden()
                }
            }
            ForEach(filteredHistory.prefix(8)) { run in
                HStack(spacing: 8) {
                    Image(systemName: icon(run.outcome))
                        .font(.caption)
                        .foregroundStyle(color(run.outcome))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary(run).isEmpty ? outcomeLabel(run) : summary(run))
                            .font(.subheadline)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(outcomeLabel(run))
                                .foregroundStyle(color(run.outcome))
                            if let d = run.duration, d > 0 {
                                Text("· \(Format.duration(d))")
                            }
                            Text("· \(run.startedAt, format: .dateTime.month().day())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if run.notes != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        repo.deleteRun(run)
                    } label: {
                        Label("Delete Run", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func summary(_ run: Run) -> String {
        let dict = run.fieldsDict
        return template.fields
            .compactMap { field in dict[field.id].flatMap { $0.isEmpty ? nil : $0 } }
            .joined(separator: " · ")
    }

    private func outcomeLabel(_ run: Run) -> String {
        template.outcomes.first { $0.result == run.outcome }?.label
            ?? run.outcome.rawValue.capitalized
    }

    private func icon(_ outcome: RunOutcome) -> String {
        switch outcome {
        case .success: "flag.fill"
        case .failure: "xmark.circle.fill"
        default: "minus.circle"
        }
    }

    private func color(_ outcome: RunOutcome) -> Color {
        switch outcome {
        case .success: .green
        case .failure: .red
        default: .gray
        }
    }
}

// MARK: - Sheets

/// Dynamic loadout entry from the template's fields.
struct RunFieldsSheet: View {
    let template: RunTemplateDTO
    var categories: [TrackerCategoryDTO] = []
    var progressed: Set<String> = []
    let title: String
    let confirm: String
    var onConfirm: ([String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                RunFieldsForm(template: template, categories: categories,
                              progressed: progressed, phase: .start, values: $values)
            }
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) {
                        onConfirm(values)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Shared dynamic form for a template's fields.
struct RunFieldsForm: View {
    enum Phase { case start, end, all }

    let template: RunTemplateDTO
    var categories: [TrackerCategoryDTO] = []
    var progressed: Set<String> = []
    var phase: Phase = .all
    @Binding var values: [String: String]

    private var visibleFields: [RunFieldDTO] {
        switch phase {
        case .all: template.fields
        case .start: template.fields.filter { !$0.isEndPhase }
        case .end: template.fields.filter { $0.isEndPhase }
        }
    }

    var body: some View {
        ForEach(visibleFields) { field in
            let options = RunFieldSupport.options(
                for: field, categories: categories,
                progressed: progressed, values: values)
            if field.kind == "multi", !options.isEmpty {
                MultiPickRow(label: field.label, options: options,
                             value: binding(field.id))
            } else if !options.isEmpty {
                Picker(field.label, selection: binding(field.id)) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    // A previously-saved value that the current narrowing
                    // excludes (weapon changed after the aspect was picked)
                    // must stay selectable, or the Picker shows nothing.
                    if let current = values[field.id], !current.isEmpty,
                       !options.contains(current) {
                        Text(current).tag(current)
                    }
                }
            } else {
                TextField(field.label, text: binding(field.id))
            }
        }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }
}

/// Several-of-many entry ("which gods showed up this run"), stored joined so
/// the Run model needs nothing new. Toggles inside a disclosure rather than a
/// menu: the list is read as much as written.
struct MultiPickRow: View {
    let label: String
    let options: [String]
    @Binding var value: String

    private var chosen: Set<String> {
        Set(value.components(separatedBy: RunFieldDTO.multiSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    var body: some View {
        DisclosureGroup {
            ForEach(options, id: \.self) { option in
                Button {
                    var set = chosen
                    if set.contains(option) { set.remove(option) } else { set.insert(option) }
                    // Preserve the options' order, not insertion order, so
                    // the stored value reads consistently.
                    value = options.filter(set.contains)
                        .joined(separator: RunFieldDTO.multiSeparator)
                } label: {
                    HStack {
                        Text(option).foregroundStyle(.primary)
                        Spacer()
                        if chosen.contains(option) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(chosen.isEmpty ? "—" : "\(chosen.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Outcome + notes when a live run ends — plus the template's end-phase
/// fields (where you died, which gods you took), which are only known now.
struct EndRunSheet: View {
    let template: RunTemplateDTO
    var categories: [TrackerCategoryDTO] = []
    var progressed: Set<String> = []
    let run: Run
    var onEnd: (RunOutcome, String?, [String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var outcomeID = ""
    @State private var notes = ""
    @State private var endValues: [String: String] = [:]

    private var hasEndFields: Bool {
        template.fields.contains { $0.isEndPhase }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Outcome", selection: $outcomeID) {
                        ForEach(template.outcomes) { o in
                            Text(o.label).tag(o.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if hasEndFields {
                    Section("This run") {
                        RunFieldsForm(template: template, categories: categories,
                                      progressed: progressed, phase: .end,
                                      values: $endValues)
                    }
                }
                Section("Notes") {
                    TextField("How did it go?", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                }
            }
            .navigationTitle("End Run")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End") {
                        let outcome = template.outcomes.first { $0.id == outcomeID }?.result ?? .neutral
                        onEnd(outcome, notes.isEmpty ? nil : notes, endValues)
                        dismiss()
                    }
                }
            }
            .onAppear {
                outcomeID = template.outcomes.first?.id ?? ""
            }
        }
        .presentationDetents(hasEndFields ? [.medium, .large] : [.medium])
    }
}

/// Manual full-run entry (fields + outcome + when + duration + notes).
struct LogRunSheet: View {
    let template: RunTemplateDTO
    var categories: [TrackerCategoryDTO] = []
    var progressed: Set<String> = []
    var onSave: ([String: String], RunOutcome, Date, TimeInterval, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var outcomeID = ""
    @State private var date = Date.now
    @State private var minutes = 20
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Loadout") {
                    RunFieldsForm(template: template, categories: categories,
                                  progressed: progressed, phase: .all, values: $values)
                }
                Section {
                    Picker("Outcome", selection: $outcomeID) {
                        ForEach(template.outcomes) { o in
                            Text(o.label).tag(o.id)
                        }
                    }
                    DatePicker("When", selection: $date)
                    Stepper("\(minutes) min", value: $minutes, in: 1...600, step: 5)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Log Run")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let outcome = template.outcomes.first { $0.id == outcomeID }?.result ?? .neutral
                        onSave(values, outcome, date, TimeInterval(minutes * 60),
                               notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                }
            }
            .onAppear {
                outcomeID = template.outcomes.first?.id ?? ""
            }
        }
    }
}
