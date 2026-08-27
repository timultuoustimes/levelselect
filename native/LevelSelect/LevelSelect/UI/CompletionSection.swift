import SwiftUI
import SwiftData

/// The game's record of being finished — every "I beat this," said as
/// precisely as it's actually known.
///
/// This is deliberately not tied to the tracker. Rolling credits is a moment
/// that happens whether or not a checklist was open at the time, and a
/// history of past clears ("beat it in 2011, on the 360") deserves recording
/// without inventing sessions or ticking a hundred boxes retroactively.
/// The tracker's own 100% is a different, more personal achievement — every
/// item on YOUR list — and gets its own label rather than being conflated.
struct CompletionSection: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @State private var marking = false
    @State private var editing: CompletionEvent?

    private var repo: Repository { Repository(context) }

    private var events: [CompletionEvent] {
        (game.completionEvents ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if events.count > 1 {
                Text("Beaten \(events.count) times")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(events, id: \.id) { event in
                CompletionRow(event: event)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(event.labelText), \(event.spanText)"
                                    + (event.companions.isEmpty ? "" : ", with \(event.companions.sentence)"))
                .accessibilityHint("Opens this record to edit")
                .contentShape(.rect)
                .onTapGesture { editing = event }
                .contextMenu {
                    Button {
                        editing = event
                    } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) {
                        repo.removeCompletion(event)
                    } label: { Label("Remove", systemImage: "trash") }
                }
            }
            if let note = events.compactMap(\.notes).first(where: { !$0.isEmpty }) {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                marking = true
            } label: {
                Label(events.isEmpty ? "Mark as Beaten…" : "Add Another…",
                      systemImage: "flag.checkered")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
        }
        .sheet(isPresented: $marking) {
            MarkCompletionSheet(game: game)
                #if !os(macOS)
                .presentationDetents([.medium, .large])
                #endif
        }
        .sheet(item: $editing) { event in
            MarkCompletionSheet(game: game, editing: event)
                #if !os(macOS)
                .presentationDetents([.medium, .large])
                #endif
        }
    }
}

/// "When, and how much of when do you actually know?"
///
/// Precision is the whole point of this sheet: an exact date for last night's
/// credits, a month for "sometime that spring," a bare year for the 2011
/// clear you're logging fifteen years later. The record stores what you said
/// and never pretends to know more.
struct MarkCompletionSheet: View {
    let game: Game
    /// When set, the sheet edits that record instead of writing a new one —
    /// a finish you misremembered by a month shouldn't have to be deleted and
    /// re-entered.
    var editing: CompletionEvent? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var label: CompletionLabel = .cleared
    @State private var customLabel = ""
    @State private var precision = "day"
    @State private var date = Date.now
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = Calendar.current.component(.month, from: .now)
    /// The start of the span. "none" = not recorded, which is the default —
    /// most historical finishes have a remembered end and a vague beginning.
    @State private var startPrecision = "none"
    @State private var startDate = Date.now
    @State private var startYear = Calendar.current.component(.year, from: .now)
    @State private var startMonth = Calendar.current.component(.month, from: .now)
    @State private var platform = ""
    @State private var notes = ""
    @State private var playedWith: [Companion] = []
    /// nil = "just the game" — a historical beat no tracked run ever saw.
    @State private var playthroughID: UUID?

    private var repo: Repository { Repository(context) }

    /// The date a precision + pickers compose to, floored the way it's stored.
    private static func compose(precision: String, date: Date, year: Int, month: Int) -> Date {
        switch precision {
        case "month":
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        case "year":
            return Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        default:
            return date
        }
    }

    private var composedFinish: Date {
        Self.compose(precision: precision, date: date, year: year, month: month)
    }

    private var composedStart: Date? {
        guard startPrecision != "none" else { return nil }
        return Self.compose(precision: startPrecision, date: startDate,
                            year: startYear, month: startMonth)
    }

    /// Fuzzy dates floor to their period's first day, so "2026 → Jan 2026"
    /// compares equal and passes; only a genuinely later start trips this.
    private var startsAfterFinish: Bool {
        guard let start = composedStart else { return false }
        return start > composedFinish
    }

    /// Release year → now, so "the year it came out" is one spin away.
    private var yearRange: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        let earliest = game.firstReleaseDate
            .map { min(Calendar.current.component(.year, from: $0), current) } ?? 1970
        return Array((earliest...current).reversed())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What happened", selection: $label) {
                        Text("Beat the game").tag(CompletionLabel.cleared)
                        Text("100% — all of my list").tag(CompletionLabel.hundredPercent)
                        Text("New Game+").tag(CompletionLabel.newGamePlus)
                        Text("Something else").tag(CompletionLabel.custom)
                    }
                    if label == .custom {
                        TextField("Call it what it was", text: $customLabel)
                    }
                } footer: {
                    if label == .hundredPercent {
                        Text("100% here means everything on your tracker — the list you chose to keep. It doesn't claim a platinum.")
                    }
                }

                Section("Finished") {
                    Picker("How precisely do you know?", selection: $precision) {
                        Text("Exact day").tag("day")
                        Text("Month").tag("month")
                        Text("Just the year").tag("year")
                    }
                    .pickerStyle(.segmented)

                    switch precision {
                    case "day":
                        DatePicker("Date", selection: $date, in: ...Date.now,
                                   displayedComponents: .date)
                    case "month":
                        Picker("Month", selection: $month) {
                            ForEach(1...12, id: \.self) {
                                Text(Calendar.current.monthSymbols[$0 - 1]).tag($0)
                            }
                        }
                        Picker("Year", selection: $year) {
                            ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                        }
                    default:
                        Picker("Year", selection: $year) {
                            ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                }

                Section {
                    Picker("Started", selection: $startPrecision) {
                        Text("Not recorded").tag("none")
                        Text("Exact day").tag("day")
                        Text("Month").tag("month")
                        Text("Just the year").tag("year")
                    }
                    switch startPrecision {
                    case "day":
                        DatePicker("Date", selection: $startDate, in: ...Date.now,
                                   displayedComponents: .date)
                    case "month":
                        Picker("Month", selection: $startMonth) {
                            ForEach(1...12, id: \.self) {
                                Text(Calendar.current.monthSymbols[$0 - 1]).tag($0)
                            }
                        }
                        Picker("Year", selection: $startYear) {
                            ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                        }
                    case "year":
                        Picker("Year", selection: $startYear) {
                            ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                        }
                    default:
                        EmptyView()
                    }
                } footer: {
                    if startsAfterFinish {
                        Text("That start is after the finish.")
                            .foregroundStyle(.red)
                    } else if startPrecision != "none" {
                        Text("A span reads like a diary line — \"Dec 2025 → Jan 2026\".")
                    }
                }

                Section {
                    if !game.livePlaythroughs.isEmpty {
                        Picker("Playthrough", selection: $playthroughID) {
                            Text("Just the game").tag(UUID?.none)
                            ForEach(game.livePlaythroughs) { pt in
                                Text(pt.name).tag(UUID?.some(pt.id))
                            }
                        }
                    }
                    if !game.platforms.isEmpty {
                        Picker("Platform", selection: $platform) {
                            Text("Not said").tag("")
                            ForEach(game.platforms, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    CompanionEditor(companions: $playedWith)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                } header: {
                    Text("Details (optional)")
                } footer: {
                    Text("\"Played with\" is just written down — the app has no accounts and doesn't share anything. It's there so a co-op finish remembers who was on the couch.")
                }
            }
            .navigationTitle(editing == nil ? "Mark as Beaten" : "Edit")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Record" : "Save") { record() }
                        .disabled((label == .custom
                                   && customLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                                  || startsAfterFinish)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let editing {
                    label = editing.label
                    customLabel = editing.customLabel ?? ""
                    precision = editing.datePrecision ?? "day"
                    date = editing.date
                    year = Calendar.current.component(.year, from: editing.date)
                    month = Calendar.current.component(.month, from: editing.date)
                    if let started = editing.startedDate {
                        startPrecision = editing.startedPrecision ?? "day"
                        startDate = started
                        startYear = Calendar.current.component(.year, from: started)
                        startMonth = Calendar.current.component(.month, from: started)
                    }
                    platform = editing.platform ?? ""
                    notes = editing.notes ?? ""
                    playedWith = editing.companions
                    return
                }
                if platform.isEmpty {
                    platform = PlatformPreference.owned(game.platforms) ?? ""
                }
                // Today's credits almost always cap the run you're on;
                // "Just the game" stays one tap away for history.
                if playthroughID == nil {
                    playthroughID = game.activePlaythrough?.id
                }
            }
        }
    }

    private func record() {
        let stored = composedFinish
        let start = composedStart
        let startPrec: String? = start == nil || startPrecision == "day" ? nil : startPrecision
        if let editing {
            repo.updateCompletion(
                editing,
                label: label,
                date: stored,
                precision: precision == "day" ? nil : precision,
                platform: platform.isEmpty ? nil : platform,
                customLabel: label == .custom ? customLabel : nil,
                notes: notes.isEmpty ? nil : notes,
                playedWith: playedWith,
                startedDate: start,
                startedPrecision: startPrec)
        } else {
            repo.addCompletion(
                to: game,
                label: label,
                date: stored,
                precision: precision == "day" ? nil : precision,
                platform: platform.isEmpty ? nil : platform,
                customLabel: label == .custom ? customLabel : nil,
                notes: notes.isEmpty ? nil : notes,
                playedWith: playedWith,
                playthrough: game.livePlaythroughs.first { $0.id == playthroughID },
                startedDate: start,
                startedPrecision: startPrec)
        }
        dismiss()
    }
}


/// One recorded finish. Extracted because the row grew past what SwiftUI's
/// type-checker will infer in one expression — four optional clauses in a
/// single HStack is where it gives up.
private struct CompletionRow: View {
    let event: CompletionEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.label == .hundredPercent
                  ? "checkmark.seal.fill" : "flag.checkered")
                .font(.caption)
                .foregroundStyle(LSTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.labelText)
                        .font(.subheadline.weight(.medium))
                    if let platform = event.platform, !platform.isEmpty {
                        Text("· \(PlatformShort.name(platform))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let run = event.playthrough {
                        Text("· \(run.name)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                CompanionLine(companions: event.companions)
            }
            Spacer(minLength: 4)
            Text(event.spanText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
