import SwiftUI
import SwiftData

/// "When did you stop?" — ends a runaway session at a user-chosen time.
struct EndSessionSheet: View {
    let session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var stopTime: Date

    /// The earliest pickable stop: the current segment's real boundary — the
    /// last resume for a running session, the pause itself for a paused one,
    /// never the original start (with pauses in between, start + threshold
    /// could suggest a stop that predates play this session recorded). The
    /// min(.now) clamp matters: a session synced from a device whose clock is
    /// ahead can carry an anchor in this device's FUTURE, and an unclamped
    /// anchor makes the DatePicker's range backwards — an invalid
    /// ClosedRange — and its default stop a time that hasn't happened.
    private static func earliestStop(for session: Session) -> Date {
        min(.now, session.resumedAt ?? session.pausedAt ?? session.startDate)
    }

    init(session: Session) {
        self.session = session
        let anchor = Self.earliestStop(for: session)
        // A paused session already stopped accruing AT its pause — that IS
        // when the user stopped, so suggest it exactly; anchor + threshold
        // would invent a stop hours after they put the game down.
        let suggested = session.state == .paused
            ? anchor
            : min(.now, anchor.addingTimeInterval(StaleSessionGuard.threshold))
        _stopTime = State(initialValue: suggested)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Game", value: session.playthrough?.game?.name ?? "—")
                    LabeledContent("Started") {
                        Text(session.startDate, format: .dateTime.month().day().hour().minute())
                    }
                }
                Section("When did you stop?") {
                    DatePicker("Stopped at", selection: $stopTime,
                               in: Self.earliestStop(for: session) ... .now)
                    LabeledContent("Records") {
                        // The same calculation the save performs, so the
                        // preview can't promise a number the write won't honour.
                        Text(Format.duration(session.elapsed(asOf: stopTime)))
                            .foregroundStyle(LSTheme.accent)
                    }
                }
            }
            .navigationTitle("End Session")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End") {
                        Repository(context).endStaleSession(session, stoppedAt: stopTime)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Edit or delete a completed session (date, duration via end time, notes).
struct EditSessionSheet: View {
    let session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    @State private var confirmingDelete = false

    init(session: Session) {
        self.session = session
        _start = State(initialValue: session.startDate)
        // NOT `session.endDate` — see `Session.editableEnd`. The stored end
        // is when the clock stopped, which for a paused or stale-ended
        // session is much later than what was played.
        _end = State(initialValue: session.editableEnd)
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker("Started", selection: $start)
                    DatePicker("Ended", selection: $end, in: start...)
                    LabeledContent("Duration") {
                        Text(Format.duration(end.timeIntervalSince(start)))
                            .foregroundStyle(LSTheme.accent)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                }
                Section {
                    Button("Delete Session", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .navigationTitle("Edit Session")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Repository(context).updateSession(session, start: start, end: end,
                                                          notes: notes)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Repository(context).deleteSession(session)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
