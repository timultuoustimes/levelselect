import SwiftUI
import SwiftData

/// Start / pause / stop / log a play session for a game, with a live timer and
/// recent-session history. Backed by `Repository`; the timer is derived from
/// timestamps (TimelineView), never a stored ticking value.
struct SessionControlsView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @State private var showingLog = false
    @State private var showingCarriedOver = false
    @State private var editing: Session?
    /// These controls keep their system button styles — `.bordered` and
    /// `LSPrimaryButtonStyle` both draw a press already — so the haptic rides
    /// on a pulse rather than on a style. See `LSPlayPulse`.
    @State private var pulse = LSPlayPulse()

    /// Store-driven, not relationship-driven. The two-device test caught the
    /// difference: a session imported from another device is INSERTED and
    /// points its to-one at the playthrough — the playthrough's own fields
    /// never change, so Observation never invalidates a view that computed
    /// its list from `pt.sessions`. With a stopped timer (no ticking
    /// TimelineView re-rendering every second) the page sat frozen: the
    /// synced 34s session was in the store for a quarter hour while "Recent"
    /// and the total still showed the pre-import numbers — indistinguishable,
    /// to the user, from data loss. A @Query observes the store itself, so
    /// remote merges re-render this section; the relationship-derived values
    /// (active playthrough, active session) recompute correctly once
    /// anything triggers the render.
    @Query private var liveSessions: [Session]

    init(game: Game) {
        self.game = game
        // One relationship hop only — a two-level chain
        // (`playthrough?.game?.id`) crashes SwiftData's predicate translation
        // at fetch time (caught by the pinning test, not on a device). The
        // id list is captured at init; the parent re-renders (and re-inits
        // this view) whenever the game record changes, which covers
        // playthroughs appearing or being removed.
        let ptIDs = game.livePlaythroughs.map(\.id)
        _liveSessions = Query(
            filter: #Predicate<Session> {
                $0.deletedAt == nil && $0.playthrough.flatMap { ptIDs.contains($0.id) } == true
            },
            sort: [SortDescriptor(\Session.startDate, order: .reverse)]
        )
    }

    private var repo: Repository { Repository(context) }

    /// The game's active (non-deleted) playthrough, if created yet.
    private var playthrough: Playthrough? {
        game.activePlaythrough
    }

    private var sessions: [Session] {
        guard let pt = playthrough else { return [] }
        return liveSessions.filter { $0.playthrough?.id == pt.id }
    }

    /// The RetroAchievements playthrough is a record of an account, not a run
    /// you sit down to play — timing against it would file real hours under
    /// something that never happened at a keyboard. The controls are hidden
    /// rather than the playthrough being locked away, because it is still
    /// worth reading.
    private var isRecordOnly: Bool {
        playthrough?.name == Repository.raPlaythroughName
            && playthrough?.notes == Repository.raPlaythroughMarker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRecordOnly {
                Label {
                    Text("Achievements earned on your RetroAchievements account, across every time you've played this. Switch playthrough to time a session.")
                } icon: {
                    Image(systemName: "trophy")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                header

                Group {
                    if let active = playthrough?.activeSession {
                        activeSessionControls(active)
                    } else {
                        idleControls
                    }
                }
                // On the group rather than on each button: stopping a session
                // REPLACES the controls, so a feedback modifier attached to
                // the Stop button is gone before the pulse can be heard.
                .lsPlayFeedback(pulse)

                if !sessions.isEmpty {
                    recentSessions
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            LogSessionSheet { duration, date, notes in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logManualSession(on: pt, duration: duration, date: date, notes: notes)
                pulse.fire(.logged)
            }
            .lsSheet()
        }
        .sheet(item: $editing) { session in
            EditSessionSheet(session: session).lsSheet()
        }
        .sheet(isPresented: $showingCarriedOver) {
            CarriedOverSheet(seconds: playthrough?.carriedOverSeconds ?? 0,
                             existingSpans: playthrough?.carriedOverSpans ?? []) { seconds, spans in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.setCarriedOver(seconds, on: pt)
                repo.setCarriedOverSpans(spans, on: pt)
            }
            .lsSheet()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                // Summed from the query results, so a synced session bumps
                // the total the moment it lands — same reason as the list.
                // Carried-over time is part of what you have played and part
                // of no session, so it is added to the number rather than
                // shown beside it as a footnote.
                let total = (playthrough?.carriedOverSeconds ?? 0)
                    + sessions.reduce(0) { $0 + $1.elapsed() }
                Text(game.livePlaythroughs.count > 1 ? "This playthrough" : "Time played")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.duration(total))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
            }
            // Said out loud as the part of the total it is: a number with no
            // session behind it would otherwise be indistinguishable from a
            // play history that had lost its sessions. It lives here rather
            // than beside Start and Log because it edits this number, and
            // because the everyday control should not grow a menu.
            if !isRecordOnly {
                let carried = playthrough?.carriedOverSeconds ?? 0
                Button { showingCarriedOver = true } label: {
                    HStack {
                        // The year rides in the label rather than as a second
                        // row: it is a qualifier on this number, not a fact
                        // of its own.
                        let year = playthrough?.carriedOverYear()
                        Text(carried > 0
                             ? (year.map { "Before tracking · \($0)" } ?? "Before tracking")
                             : "Add time played before tracking")
                            .font(.caption)
                        Spacer()
                        if carried > 0 {
                            Text(Format.duration(carried))
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .lsTapTargetTall(6)
            }
            if game.livePlaythroughs.count > 1 {
                HStack {
                    Text("All playthroughs")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    // The query is already scoped to live playthroughs.
                    let all = game.livePlaythroughs.reduce(0) { $0 + $1.carriedOverSeconds }
                        + liveSessions.reduce(0) { $0 + $1.elapsed() }
                    Text(Format.duration(all))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func activeSessionControls(_ active: Session) -> some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.clock(active.elapsed(asOf: ctx.date)))
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(active.state == .running ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.primary))
            }
            .background {
                if active.state == .running { LivePulse() }
            }
            HStack {
                if active.state == .running {
                    Button {
                        pulse.fire(.housekeeping)
                        repo.pauseSession(active)
                    } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.bordered)
                } else {
                    // Resuming IS starting to play, so it thumps like Play.
                    Button {
                        pulse.fire(.play)
                        repo.resumeSession(active)
                    } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) {
                    pulse.fire(.housekeeping)
                    repo.stopSession(active)
                } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var idleControls: some View {
        HStack {
            Button {
                pulse.fire(.play)
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.startSession(on: pt)
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            // The palette's button, not the system's: accent fill, the
            // pair's step as ink and as the hard edge beneath — white text
            // on a light ground was the giveaway. See `LSPrimaryButtonStyle`.
            .buttonStyle(LSPrimaryButtonStyle())

            Button {
                showingLog = true
            } label: {
                Label("Log", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent — tap to edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // The way out of the five.
                //
                // Five is the right number HERE — "what have I been doing
                // lately" wants five. But it was also the only list of
                // sessions in the app, so on a long-running game everything
                // older was unreachable and, since this row is the only route
                // to EditSessionSheet, uneditable. Counts every playthrough,
                // not just the active one, because that is what the history
                // screen shows.
                if liveSessions.count > 5 {
                    NavigationLink {
                        SessionHistoryView(game: game)
                    } label: {
                        Text("See all \(liveSessions.count)")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
                }
            }
            ForEach(sessions.prefix(5)) { s in
                Button {
                    if s.state == .stopped { editing = s }
                } label: {
                    HStack {
                        Image(systemName: s.isManual ? "square.and.pencil" : "stopwatch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(s.startDate, format: .dateTime.month().day().hour().minute())
                            .font(.subheadline)
                        if s.notes != nil {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Format.duration(s.elapsed()))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        // Only a stopped session opens the editor, so only a
                        // stopped session gets the affordance that says so.
                        // The live one sat here wearing a chevron under a
                        // heading reading "tap to edit", and did nothing.
                        if s.state == .stopped {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(s.state == .running ? "running" : "paused")
                                .font(.caption2)
                                .foregroundStyle(LSTheme.accent)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal manual-session entry: hours + minutes + optional note.
struct LogSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (_ duration: TimeInterval, _ date: Date, _ notes: String?) -> Void

    @State private var hours = 0
    @State private var minutes = 30
    @State private var date = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            LSForm {
                Section("Duration") {
                    Stepper("\(hours) h", value: $hours, in: 0...100)
                    Stepper("\(minutes) m", value: $minutes, in: 0...59, step: 5)
                }
                Section("When") {
                    DatePicker("Date", selection: $date)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .lsFormStyle()
            .navigationTitle("Log Session")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let dur = TimeInterval(hours * 3600 + minutes * 60)
                        onSave(dur, date, notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                    .disabled(hours == 0 && minutes == 0)
                }
            }
        }
    }
}

/// Time played before the app was tracking it.
///
/// A duration and nothing else — no date, because there isn't one, and that
/// absence is the whole point. Steam says 42 hours and cannot say when; the
/// only way to keep that number until now was one enormous manual session
/// dated the day you typed it, which files a play in the Journal on a day
/// nothing happened. Tim: *"being able to put that in, and then add your
/// sessions after that to the number as you continue to play."*
struct CarriedOverSheet: View {
    @Environment(\.dismiss) private var dismiss
    let seconds: TimeInterval
    /// Which years these hours belong to, if anybody has said.
    var existingSpans: [CarriedOverSpan] = []
    var onSave: (TimeInterval, [CarriedOverSpan]) -> Void

    @State private var hours = 0
    @State private var minutes = 0
    @State private var spans: [CarriedOverSpan] = []

    /// Hours not yet placed in any year.
    private var remaining: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60) - spans.totalSeconds
    }

    private var spansFooter: String {
        if spans.isEmpty {
            return "Optional, and only as exact as you actually are. Hours you place land in those years' Replays as a line of their own — never spread across days, because nobody knows which days they were."
        }
        if remaining > 60 {
            return "\(Format.duration(remaining)) isn't placed in any year yet. That's fine — it still counts toward the total."
        }
        if remaining < -60 {
            return "You've placed more time than the total above. Raise the total, or take some back."
        }
        return "All of it is placed. A range is shown whole on each year it covers, because you said the span rather than the year."
    }

    private func yearPicker(_ label: String, _ selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(years, id: \.self) { year in
                Text(String(year)).tag(year)
            }
        }
        .pickerStyle(.menu)
    }

    /// This year back to 1972 — the Odyssey. Long enough that nobody's
    /// history falls off the end of it.
    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: .now)
        return Array((1972...thisYear).reversed())
    }

    var body: some View {
        NavigationStack {
            LSForm {
                Section {
                    Stepper("\(hours) h", value: $hours, in: 0...9_999)
                    Stepper("\(minutes) m", value: $minutes, in: 0...59, step: 5)
                } header: {
                    Text("Time played before tracking")
                } footer: {
                    Text("The number your console or storefront already knows — Steam's hours, a Switch profile's. It adds to this game's total and stays out of your session history, because it never happened on any one day. Set it to zero to remove it.")
                }
                // **The one thing the API can't tell us and you can.**
                // Steam hands over a lifetime total with no dates, so these
                // hours sit outside every dated view. Naming the years puts
                // them back into those years' Replays — and only there,
                // because a year is not a day and the heatmap stays honest.
                Section {
                    ForEach($spans) { $span in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Stepper("\(Int(span.seconds) / 3600) h",
                                        value: Binding(
                                            get: { Int(span.seconds) / 3600 },
                                            set: { span.seconds = TimeInterval($0 * 3600) }),
                                        in: 0...9_999)
                            }
                            HStack(spacing: 8) {
                                yearPicker("From", $span.fromYear)
                                yearPicker("To", $span.toYear)
                            }
                            if !span.isSingleYear {
                                Text("Shown whole on each year from \(span.fromYear) to \(span.toYear), and divided between none of them.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { spans.remove(atOffsets: $0) }
                    Button {
                        let thisYear = Calendar.current.component(.year, from: .now)
                        spans.append(CarriedOverSpan(
                            seconds: max(0, remaining), fromYear: thisYear))
                    } label: {
                        Label("Add years", systemImage: "plus")
                    }
                } header: {
                    Text("When was it?")
                } footer: {
                    Text(spansFooter)
                }
            }
            .lsFormStyle()
            .navigationTitle("Starting total")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Spans with no time in them are noise rather than a
                        // claim, and are dropped on the way out.
                        onSave(TimeInterval(hours * 3600 + minutes * 60),
                               spans.filter { $0.seconds > 0 })
                        dismiss()
                    }
                }
            }
            .onAppear {
                hours = Int(seconds) / 3600
                minutes = (Int(seconds) % 3600) / 60
                spans = existingSpans
            }
        }
    }
}
