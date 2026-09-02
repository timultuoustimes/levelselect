import SwiftUI
import SwiftData

/// Writing down something that happened before the app was watching.
///
/// The date input is the whole design. Every other date field in this app is a
/// `DatePicker`, which silently insists you know the day — and the entries
/// people most want here are the ones they know least precisely. A form that
/// demands a real date quietly excludes childhood, which is exactly the part
/// worth writing down.
///
/// So precision is a *choice*, and "I'm not sure" is a first-class answer
/// rather than a failure to fill something in.
struct MemorySheet: View {
    /// nil when writing a new one.
    let existing: Memory?
    /// Pre-attached when opened from a game.
    var game: Game?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body_ = ""
    @State private var kind = "memory"
    @State private var place = ""
    @State private var platform = ""

    @State private var howKnown: HowKnown = .day
    @State private var date = Date.now
    @State private var words = ""
    @State private var fromYear = 1995
    @State private var toYear = 1996

    /// How well the date is known — and the fourth case is the point.
    enum HowKnown: String, CaseIterable, Identifiable {
        case day, month, year, unsure
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day:    "Exact day"
            case .month:  "Month"
            case .year:   "Year"
            case .unsure: "Not sure"
            }
        }
        /// The stored precision. `unsure` is **nil**, not a precision: "1995
        /// or 1996" is two years, and no single grain describes it.
        var precision: String? {
            switch self {
            case .day:    "day"
            case .month:  "month"
            case .year:   "year"
            case .unsure: nil
            }
        }
    }

    init(existing: Memory? = nil, game: Game? = nil) {
        self.existing = existing
        self.game = game
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $title)
                    TextField("Anything more", text: $body_, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Picker("How well do you know it?", selection: $howKnown) {
                        ForEach(HowKnown.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch howKnown {
                    case .day:
                        DatePicker("When", selection: $date, displayedComponents: .date)
                    case .month, .year:
                        // The same picker, and the app throws away what it was
                        // not told: a month-precision memory keeps the month
                        // and prints only that.
                        DatePicker("Around when", selection: $date, displayedComponents: .date)
                    case .unsure:
                        TextField("Christmas 1995 or 1996", text: $words)
                        Stepper("From \(fromYear)", value: $fromYear, in: 1970...2100)
                        Stepper("To \(toYear)", value: $toYear, in: 1970...2100)
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text(footerText)
                }

                Section("What kind") {
                    Picker("Kind", selection: $kind) {
                        Text("Just a memory").tag("memory")
                        ForEach(Memory.kindLabels.sorted(by: { $0.value < $1.value }), id: \.key) {
                            Text($0.value).tag($0.key)
                        }
                    }
                    TextField("Console or platform", text: $platform)
                    TextField("Where (a place name, not an address)", text: $place)
                }
            }
            .navigationTitle(existing == nil ? "New memory" : "Memory")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Says what will be *kept*, because the honest surprise of this form is
    /// that choosing "Year" discards the month and day you can see in the
    /// picker — and it should say so before you wonder where they went.
    private var footerText: String {
        switch howKnown {
        case .day:    "Stored and shown as an exact day."
        case .month:  "Only the month and year are kept."
        case .year:   "Only the year is kept."
        case .unsure: "Shown exactly as you write it. The years are only used to place it on the timeline."
        }
    }

    private func load() {
        guard let existing else { return }
        title = existing.title
        body_ = existing.body ?? ""
        kind = existing.kind
        place = existing.place ?? ""
        platform = existing.platform ?? ""
        date = existing.earliest
        words = existing.whenText ?? ""
        howKnown = HowKnown.allCases.first { $0.precision == existing.precision } ?? .unsure
        fromYear = Memory.calendar.component(.year, from: existing.earliest)
        toYear = Memory.calendar.component(.year, from: existing.latest)
    }

    private func save() {
        let memory = existing ?? Memory()
        memory.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.body = body_.journalText
        memory.kind = kind
        memory.place = place.journalText
        memory.platform = platform.journalText
        if memory.game == nil { memory.game = game }

        let repo = Repository(context)
        if howKnown == .unsure {
            let low = min(fromYear, toYear), high = max(fromYear, toYear)
            let start = Memory.calendar.date(from: DateComponents(year: low, month: 1, day: 1)) ?? date
            let end = Memory.calendar.date(from: DateComponents(year: high, month: 12, day: 31)) ?? date
            repo.saveMemory(memory, on: start, precision: nil,
                            words: words, span: start...end)
        } else {
            repo.saveMemory(memory, on: date, precision: howKnown.precision, words: nil)
        }
        dismiss()
    }
}
