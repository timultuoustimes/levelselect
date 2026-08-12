import SwiftUI
import SwiftData

/// Start / pause / stop / log a play session for a game, with a live timer and
/// recent-session history. Backed by `Repository`; the timer is derived from
/// timestamps (TimelineView), never a stored ticking value.
struct SessionControlsView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @State private var showingLog = false
    @State private var editing: Session?

    private var repo: Repository { Repository(context) }

    /// The game's active (non-deleted) playthrough, if created yet.
    private var playthrough: Playthrough? {
        game.activePlaythrough
    }

    private var sessions: [Session] {
        (playthrough?.sessions ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let active = playthrough?.activeSession {
                activeSessionControls(active)
            } else {
                idleControls
            }

            if !sessions.isEmpty {
                recentSessions
            }
        }
        .sheet(isPresented: $showingLog) {
            LogSessionSheet { duration, date, notes in
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logManualSession(on: pt, duration: duration, date: date, notes: notes)
            }
        }
        .sheet(item: $editing) { session in
            EditSessionSheet(session: session)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                let total = playthrough?.totalPlaytime() ?? 0
                Text(game.livePlaythroughs.count > 1 ? "This playthrough" : "Total played")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.duration(total))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
            }
            if game.livePlaythroughs.count > 1 {
                HStack {
                    Text("All playthroughs")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    let all = game.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }
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
                        repo.pauseSession(active)
                    } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        repo.resumeSession(active)
                    } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) {
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
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.startSession(on: pt)
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

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
            Text("Recent — tap to edit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
            Form {
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
