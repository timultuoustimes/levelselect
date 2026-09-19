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
    /// Default to *this* year, not a hard-coded 1995.
    ///
    /// Tapping "+" on a day in March 2024 and choosing "Not sure" offered
    /// 1995–1996, saved the memory into 1995, and it vanished from the month
    /// the user was standing in — thirty years back up the year strip. See
    /// `load()`, which seeds these from the tapped day when there is one.
    @State private var fromYear = Memory.calendar.component(.year, from: .now)
    @State private var toYear = Memory.calendar.component(.year, from: .now)
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
    /// The grain to come back to when "Do you know when?" is switched on again.
    @State private var lastGrain: HowKnown = .day
    @State private var importing = false
    @State private var importError: String?
    /// A memory being written has no record yet, so a photo picked before the
    /// first save is held here and attached once there is something to attach
    /// it to. Losing a photo because you had not saved yet would be its own
    /// small betrayal.
    @State private var pendingPhotos: [PendingPhoto] = []

    /// A picture chosen before the memory has a record to hang it on.
    ///
    /// Identified rather than indexed: `ForEach(enumerated(), id: \.offset)`
    /// re-numbers every item the moment one is removed, so a remove button
    /// keyed on offset deletes the wrong picture as soon as there are two.
    struct PendingPhoto: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// How well the date is known — and the fourth case is the point.
    enum HowKnown: String, CaseIterable, Identifiable {
        case day, month, season, year, decade, unsure

        /// The five that describe a date. `unsure` is the absence of one, and
        /// putting it in the same control as its own peers is what made six.
        static var grains: [HowKnown] { allCases.filter { $0 != .unsure } }
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day:    "Day"
            case .month:  "Month"
            case .season: "Season"
            case .year:   "Year"
            case .decade: "Decade"
            case .unsure: "Not sure"
            }
        }
        /// The stored precision. `unsure` is **nil**, not a precision: "1995
        /// or 1996" is two years, and no single grain describes it.
        var precision: String? {
            switch self {
            case .day:    "day"
            case .month:  "month"
            case .season: "season"
            case .year:   "year"
            case .decade: "decade"
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
                    // **A switch and five segments, not six segments.**
                    //
                    // "Not sure" was a peer of "Day" in one segmented control,
                    // which made six peers — and at the DEFAULT text size the
                    // last one already truncated to "Not s…" before anyone had
                    // touched it, worse at every size above. Fable argued the
                    // restructure when the control had four segments, it was
                    // declined, Season and Decade then made it six, and the
                    // truncation is the evidence: *"the last segment truncates
                    // before anyone has touched it."*
                    //
                    // "Not sure" is not a sixth grain. It is the absence of
                    // one — the state where no precision is stored at all and
                    // only your own words say when — so it belongs where every
                    // other absence in this app lives: an off state. Same data
                    // model, one fewer segment, no truncation, and the copy
                    // below already said as much.
                    Toggle("Do you know when?", isOn: Binding(
                        get: { howKnown != .unsure },
                        set: { known in
                            if known {
                                howKnown = lastGrain
                            } else {
                                lastGrain = howKnown
                                howKnown = .unsure
                            }
                        }))
                    .tint(LSTheme.accent)

                    if howKnown != .unsure {
                        Picker("How well do you know it?", selection: $howKnown) {
                            ForEach(HowKnown.grains) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        // Remember the grain, so flicking the switch off and
                        // back on returns you to Season rather than to Day.
                        .onChange(of: howKnown) { _, new in
                            if new != .unsure { lastGrain = new }
                        }
                    }

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
                    case .month, .season, .year, .decade:
                        // The same picker, and the app throws away what it was
                        // not told: a month-precision memory keeps the month
                        // and prints only that. A season keeps the three months
                        // around the one you land on; a decade keeps the ten
                        // years around it.
                        DatePicker("Around when", selection: $date, displayedComponents: .date)
                            .lsMemoryCalendar()
                        if howKnown == .season {
                            // The words are the user's, always. The stored
                            // months are northern-hemisphere and never shown —
                            // see `Memory.seasonInterval`.
                            TextField("Summer 1998", text: $words)
                        }
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
                                        thumb(data)
                                            .overlay(alignment: .topTrailing) {
                                                removeButton("Remove picture") {
                                                    Repository(context).softDelete(image)
                                                }
                                            }
                                            // The long-press the rest of the
                                            // app already uses for this, kept
                                            // so the gesture means one thing
                                            // everywhere.
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    Repository(context).softDelete(image)
                                                } label: {
                                                    Label("Remove", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                ForEach(pendingPhotos) { photo in
                                    thumb(photo.data)
                                        .opacity(0.7)
                                        .overlay(alignment: .topTrailing) {
                                            removeButton("Remove picture") {
                                                pendingPhotos.removeAll { $0.id == photo.id }
                                            }
                                        }
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

                // **"What kind — Just a memory"** was the row, and it read
                // as a form arguing with itself: a header asking a question, a
                // label repeating it, and an answer apologizing for being the
                // default. Fable's 3.4. The header now names the group, the
                // label names the control, and the default kind is just what
                // it is — an entry that is a memory rather than an acquisition
                // or a sale. The other five kinds are real and stay.
                Section("Kind of entry") {
                    Picker("Kind", selection: $kind) {
                        Text("Memory").tag("memory")
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
        // The segment above already says "Exact day"; repeating it told
        // nobody anything.
        case .day:    ""
        case .month:  "Only the month and year are kept."
        case .season: "Shown exactly as you write it. The three months around the date are only used to place it in the year."
        case .year:   "Only the year is kept."
        case .decade: "Only the decade is kept — it sits under its own heading rather than on any one year."
        case .unsure: dayKnown
            // Both candidate years now, not just the first.
            ? "Shown exactly as you write it. It sits on that day in every year it might have been, marked as uncertain."
            : "Shown exactly as you write it. It sits under the year rather than on a day, because you haven't named one."
        }
    }

    /// Pictures already attached, newest first.
    private func thumb(_ data: Data) -> some View {
        LocalArtworkThumb(data: data, contentMode: .fill)
            .frame(width: 84, height: 84)
            .clipShape(.rect(cornerRadius: 10))
    }

    /// **Visible, not only a long-press.** `MediaSection` hides removal in a
    /// context menu, which is right on a page you are mostly reading — but
    /// this is the editor, and a picture you have just added is the thing most
    /// likely to want undoing. Tim, having added one: *"I can't remove the
    /// photo from the memory."*
    ///
    /// No confirmation: removing is a soft delete, the same as everywhere else
    /// pictures are removed.
    ///
    /// The picture is recoverable rather than gone — and as of build 37 that
    /// is true rather than aspirational. It lands in Recently Deleted with a
    /// Restore beside it and keeps for thirty days.
    ///
    /// It said this for two schema versions while `restore(_ image:)` had no
    /// caller at all, which is how a removed picture became invisible,
    /// unrecoverable AND permanent, all at once. Codex data #4.
    private func removeButton(_ label: String,
                              action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(3)
        // A `.body` glyph in 3 points of padding is about 23. It sits alone
        // in the corner of a thumbnail, so unlike the chips it can grow on
        // every side without stealing a neighbour's tap. Codex A7.
        .lsTapTargetInline()
        .accessibilityLabel(label)
    }

    /// Oldest first — the same order the detail page shows.
    ///
    /// These two disagreed: the detail led with the first photo added and this
    /// sheet listed the newest first, so removing "the first thumbnail" here
    /// deleted the last-added picture, which is not the one anyone was looking
    /// at. Fable runtime 2.13.
    private var photos: [GameImage] {
        (existing?.images ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.addedAt < $1.addedAt }
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
                pendingPhotos.append(PendingPhoto(data: raw))
            }
        } catch ImageIngest.Failure.unreadable {
            importError = "That file isn't an image this device can read."
        } catch {
            importError = "Couldn't add that picture."
        }
    }

    private func load() {
        guard let existing else {
            if let initialDate {
                date = initialDate
                // The uncertain years follow the tapped day too, so switching
                // to "Not sure" cannot file the memory in a different decade
                // from the one the user was looking at.
                let year = Memory.calendar.component(.year, from: initialDate)
                fromYear = year
                toYear = year
            }
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
                            words: words, span: start...end,
                            // The sheet already asked; the app should not have
                            // to guess it back out of the stored dates later.
                            dayKnown: dayKnown)
        } else {
            // A season carries the words it was written with — "summer 1998"
            // is what gets shown, and the stored months only decide where it
            // sorts. Every other precision re-renders exactly, so storing a
            // copy of the words would only give the two a chance to disagree.
            repo.saveMemory(memory, on: date, precision: howKnown.precision,
                            words: howKnown == .season ? words : nil)
        }
        for data in pendingPhotos.map(\.data) {
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
