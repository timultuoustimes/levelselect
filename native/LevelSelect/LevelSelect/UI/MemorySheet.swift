import SwiftUI
import SwiftData
import PhotosUI

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
    /// The day a new memory starts on. Set when it was created by tapping a
    /// square in the calendar — the date is already answered, so the form
    /// should not ask again.
    var initialDate: Date?

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
    /// **"Christmas 1995 or 1996" knows the day perfectly well.** Only the
    /// year is in doubt. Storing the span as 1 January → 31 December threw the
    /// day away and put a Christmas on a square nearer the *previous*
    /// Christmas than either of the two it might have been. Tim: *"I'd rather
    /// it pick one of the days and tell me it might be a different year, than
    /// pick just January 1."*
    @State private var dayKnown = false
    @State private var vagueMonth = 12
    @State private var vagueDay = 25

    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?
    /// A memory being written has no record yet, so a photo picked before the
    /// first save is held here and attached once there is something to attach
    /// it to. Losing a photo because you had not saved yet would be its own
    /// small betrayal.
    @State private var pendingPhotos: [Data] = []

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

    init(existing: Memory? = nil, game: Game? = nil, initialDate: Date? = nil) {
        self.existing = existing
        self.game = game
        self.initialDate = initialDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $title)
                    TextField("Anything more", text: $body_, axis: .vertical)
                        // Open-ended. A cap of 8 turned the field into a tiny
                        // scroller at exactly the point someone had something
                        // to say — nobody is writing a novel here, but the box
                        // should not be the thing that stops them.
                        .lineLimit(3...)
                }

                Section {
                    Picker("How well do you know it?", selection: $howKnown) {
                        ForEach(HowKnown.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch howKnown {
                    case .day:
                        // **Shown in the calendar it is stored in.** A Memory's
                        // dates are UTC calendar facts, so a picker left in the
                        // device's timezone renders UTC midnight on the 5th as
                        // the 4th — the app showing someone a different day
                        // from the one it just saved. Tapping the 5th on the
                        // calendar grid is where that first bit.
                        DatePicker("When", selection: $date, displayedComponents: .date)
                            .lsMemoryCalendar()
                    case .month, .year:
                        // The same picker, and the app throws away what it was
                        // not told: a month-precision memory keeps the month
                        // and prints only that.
                        DatePicker("Around when", selection: $date, displayedComponents: .date)
                            .lsMemoryCalendar()
                    case .unsure:
                        TextField("Christmas 1995 or 1996", text: $words)
                        // `verbatim:`, because interpolating an Int into a
                        // LocalizedStringKey groups it — the stepper read
                        // "From 1,995". A year is a label, not a quantity.
                        Stepper(value: $fromYear, in: 1970...2100) {
                            Text(verbatim: "From \(fromYear)")
                        }
                        Stepper(value: $toYear, in: 1970...2100) {
                            Text(verbatim: "To \(toYear)")
                        }
                        // Optional, because "sometime in 1995 or 1996" is a
                        // real answer too — and a form that demanded a day
                        // here would be the exact thing this picker exists to
                        // avoid.
                        Toggle("I know the day", isOn: $dayKnown.animation())
                        if dayKnown {
                            Picker("Month", selection: $vagueMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    // **Names from the user's calendar, not
                                    // the storage one.** `Memory.calendar` is
                                    // a bare UTC Gregorian with no locale, and
                                    // its symbols come back as "M12". Which
                                    // month a memory is stored in is a data
                                    // question; what that month is *called* is
                                    // the reader's.
                                    Text(Calendar.current.standaloneMonthSymbols[month - 1])
                                        .tag(month)
                                }
                            }
                            Picker("Day", selection: $vagueDay) {
                                ForEach(1...31, id: \.self) {
                                    Text(verbatim: "\($0)").tag($0)
                                }
                            }
                        }
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text(footerText)
                }

                Section {
                    if !photos.isEmpty || !pendingPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos) { image in
                                    if let data = image.data {
                                        LocalArtworkThumb(data: data, contentMode: .fill)
                                            .frame(width: 84, height: 84)
                                            .clipShape(.rect(cornerRadius: 10))
                                    }
                                }
                                ForEach(Array(pendingPhotos.enumerated()), id: \.offset) { _, data in
                                    LocalArtworkThumb(data: data, contentMode: .fill)
                                        .frame(width: 84, height: 84)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .opacity(0.7)
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        if importing {
                            HStack(spacing: 6) { ProgressView(); Text("Adding…") }
                        } else {
                            Label("Add a picture", systemImage: "photo.badge.plus")
                        }
                    }
                    .disabled(importing)
                    if let importError {
                        Text(importError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Pictures")
                } footer: {
                    // The reason the feature exists, said once where it lands.
                    Text("A photo of the day itself. Pictures are downscaled and kept in your own iCloud, like every other picture you add.")
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
            .task(id: photoItem) { await ingestPickedPhoto() }
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
        case .unsure: dayKnown
            ? "Shown exactly as you write it. It sits on that day in the first year, marked as uncertain."
            : "Shown exactly as you write it. The years are only used to place it on the timeline."
        }
    }

    /// Pictures already attached, newest first.
    private var photos: [GameImage] {
        (existing?.images ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.addedAt > $1.addedAt }
    }

    private func ingestPickedPhoto() async {
        guard let photoItem else { return }
        importing = true
        importError = nil
        defer { importing = false; self.photoItem = nil }
        do {
            guard let raw = try await photoItem.loadTransferable(type: Data.self) else {
                importError = "That photo couldn't be read."
                return
            }
            if let existing {
                try Repository(context).addImage(to: existing, data: raw)
            } else {
                // Held until Save makes a record to hang it on.
                pendingPhotos.append(raw)
            }
        } catch ImageIngest.Failure.unreadable {
            importError = "That file isn't an image this device can read."
        } catch {
            importError = "Couldn't add that picture."
        }
    }

    private func load() {
        guard let existing else {
            if let initialDate { date = initialDate }
            return
        }
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
        // A stored 1 January → 31 December span is what "no day" looks like;
        // anything else is carrying one.
        let from = Memory.calendar.dateComponents([.month, .day], from: existing.earliest)
        let to = Memory.calendar.dateComponents([.month, .day], from: existing.latest)
        dayKnown = !(from.month == 1 && from.day == 1 && to.month == 12 && to.day == 31)
        if dayKnown {
            vagueMonth = from.month ?? 12
            vagueDay = from.day ?? 25
        }
    }

    /// The chosen day in a given year, clamped to that month's real length.
    ///
    /// 29 February is the case that makes this necessary: the year is the part
    /// nobody is sure of, so the day can legitimately not exist in one of the
    /// candidates.
    private func vagueDate(year: Int) -> Date? {
        var parts = DateComponents(year: year, month: vagueMonth, day: 1)
        guard let first = Memory.calendar.date(from: parts),
              let length = Memory.calendar.range(of: .day, in: .month, for: first)
        else { return nil }
        parts.day = min(vagueDay, length.count)
        return Memory.calendar.date(from: parts)
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
            // With a day, the span runs candidate-to-candidate rather than
            // year-to-year. It is still every instant the memory might be —
            // and a narrower, truer interval than the old one — but it no
            // longer *starts* on a day the memory never claimed.
            let start = (dayKnown ? vagueDate(year: low) : nil)
                ?? Memory.calendar.date(from: DateComponents(year: low, month: 1, day: 1)) ?? date
            let end = (dayKnown ? vagueDate(year: high) : nil)
                ?? Memory.calendar.date(from: DateComponents(year: high, month: 12, day: 31)) ?? date
            repo.saveMemory(memory, on: start, precision: nil,
                            words: words, span: start...end)
        } else {
            repo.saveMemory(memory, on: date, precision: howKnown.precision, words: nil)
        }
        for data in pendingPhotos {
            try? repo.addImage(to: memory, data: data)
        }
        dismiss()
    }
}

private extension View {
    /// Renders a date control in `Memory.calendar` rather than the device's.
    ///
    /// Applied per control rather than to the enclosing `Section`: a modifier
    /// on a Section is applied to each child, which is harmless for
    /// `environment` but has bitten this app before with presentation
    /// modifiers — so the habit is to attach to the view that needs it.
    func lsMemoryCalendar() -> some View {
        environment(\.calendar, Memory.calendar)
            .environment(\.timeZone, Memory.calendar.timeZone)
    }
}
