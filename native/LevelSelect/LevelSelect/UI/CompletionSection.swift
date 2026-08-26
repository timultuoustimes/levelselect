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

    private var repo: Repository { Repository(context) }

    private var events: [CompletionEvent] {
        (game.completionEvents ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events, id: \.id) { event in
                HStack(spacing: 8) {
                    Image(systemName: event.label == .hundredPercent
                          ? "checkmark.seal.fill" : "flag.checkered")
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent)
                    Text(event.labelText)
                        .font(.subheadline.weight(.medium))
                    if let platform = event.platform, !platform.isEmpty {
                        Text("· \(PlatformShort.name(platform))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(event.dateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(event.labelText), \(event.dateText)")
                .contextMenu {
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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var label: CompletionLabel = .cleared
    @State private var customLabel = ""
    @State private var precision = "day"
    @State private var date = Date.now
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var platform = ""
    @State private var notes = ""

    private var repo: Repository { Repository(context) }

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

                Section("When") {
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

                Section("Details (optional)") {
                    if !game.platforms.isEmpty {
                        Picker("Platform", selection: $platform) {
                            Text("Not said").tag("")
                            ForEach(game.platforms, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                }
            }
            .navigationTitle("Mark as Beaten")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") { record() }
                        .disabled(label == .custom
                                  && customLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if platform.isEmpty {
                    platform = PlatformPreference.owned(game.platforms) ?? ""
                }
            }
        }
    }

    private func record() {
        let stored: Date
        switch precision {
        case "month":
            stored = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        case "year":
            stored = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        default:
            stored = date
        }
        repo.addCompletion(
            to: game,
            label: label,
            date: stored,
            precision: precision == "day" ? nil : precision,
            platform: platform.isEmpty ? nil : platform,
            customLabel: label == .custom ? customLabel : nil,
            notes: notes.isEmpty ? nil : notes)
        dismiss()
    }
}
