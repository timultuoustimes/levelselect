import SwiftUI
import SwiftData

/// "When did you stop?" — ends a runaway session at a user-chosen time.
struct EndSessionSheet: View {
    let session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var stopTime: Date

    init(session: Session) {
        self.session = session
        // Default from the point the current segment actually started, not
        // from the original start — with a pause in between, start + threshold
        // could land BEFORE the last resume and suggest a stop time that
        // predates the play it's meant to be recording.
        let anchor = session.resumedAt ?? session.startDate
        let suggested = min(.now, anchor.addingTimeInterval(StaleSessionGuard.threshold))
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
                               in: (session.resumedAt ?? session.startDate) ... .now)
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
        _end = State(initialValue: session.endDate
                     ?? session.startDate.addingTimeInterval(session.accumulatedDuration))
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
