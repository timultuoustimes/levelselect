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

    private var repo: Repository { Repository(context) }
    private var playthrough: Playthrough? { game.activePlaythrough }
    private var runs: [Run] { playthrough?.liveRuns ?? [] }

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

            if !runs.isEmpty {
                history
            }
        }
        .sheet(isPresented: $startingRun) {
            RunFieldsSheet(template: template, title: "Start Run", confirm: "Start") { fields in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.startRun(on: pt, fields: fields)
            }
        }
        .sheet(isPresented: $loggingRun) {
            LogRunSheet(template: template) { fields, outcome, started, duration, notes in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logRun(on: pt, fields: fields, outcome: outcome,
                            started: started, duration: duration, notes: notes)
            }
        }
        .sheet(item: $endingRun) { run in
            EndRunSheet(template: template, run: run) { outcome, notes in
                repo.endRun(run, outcome: outcome, notes: notes)
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

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(runs.filter { $0.outcome != .inProgress }.prefix(8)) { run in
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
    let title: String
    let confirm: String
    var onConfirm: ([String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                RunFieldsForm(template: template, values: $values)
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
    let template: RunTemplateDTO
    @Binding var values: [String: String]

    var body: some View {
        ForEach(template.fields) { field in
            if field.kind == "select", !field.options.isEmpty {
                Picker(field.label, selection: binding(field.id)) {
                    Text("—").tag("")
                    ForEach(field.options, id: \.self) { Text($0).tag($0) }
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

/// Outcome + notes when a live run ends.
struct EndRunSheet: View {
    let template: RunTemplateDTO
    let run: Run
    var onEnd: (RunOutcome, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var outcomeID = ""
    @State private var notes = ""

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
                        onEnd(outcome, notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                }
            }
            .onAppear {
                outcomeID = template.outcomes.first?.id ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

/// Manual full-run entry (fields + outcome + when + duration + notes).
struct LogRunSheet: View {
    let template: RunTemplateDTO
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
                    RunFieldsForm(template: template, values: $values)
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
