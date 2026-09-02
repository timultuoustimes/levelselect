import SwiftUI
import SwiftData

/// The tab that used to be Stats.
///
/// History is the noun; the charts are one way of reading it. Through build 35
/// the charts *were* the tab, which made "Stats" the app's word for your past —
/// and a page of aggregates is a poor name for a past you actually lived. The
/// journal takes the tab and the charts become a lens inside it, which is the
/// same record set rendered two ways rather than two places competing to be
/// where your history lives.
///
/// Deliberately not a fifth tab: two of five would have been "your history",
/// with no rule telling anyone which one they wanted.
///
/// This view owns the `NavigationStack`, the title and the destinations so both
/// lenses push onto the same stack; each lens keeps its own toolbar, which
/// SwiftUI merges in.
struct JournalTab: View {
    enum Lens: String, CaseIterable, Identifiable {
        case timeline, charts
        var id: String { rawValue }
        var label: String {
            switch self {
            case .timeline: "Timeline"
            case .charts:   "Charts"
            }
        }
        var icon: String {
            switch self {
            case .timeline: "list.bullet.indent"
            case .charts:   "chart.bar.fill"
            }
        }
    }

    /// Device-local, like the card order and the flip states it sits above —
    /// how you read your history on the phone isn't obviously the same answer
    /// as on the iPad on the desk.
    @AppStorage("journalLens") private var lensRaw = Lens.timeline.rawValue
    private var lens: Lens { Lens(rawValue: lensRaw) ?? .timeline }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned rather than scrolled with the content: this is how you
                // move between the two halves of the tab, so it does not get to
                // disappear once you are reading.
                Picker("View", selection: Binding(
                    get: { lens },
                    set: { lensRaw = $0.rawValue })) {
                    ForEach(Lens.allCases) { lens in
                        Label(lens.label, systemImage: lens.icon).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch lens {
                case .timeline: JournalTimeline()
                case .charts:   StatsCards()
                }
            }
            .lsBackground()
            .navigationTitle("Journal")
            // Glass, like Home — see LibraryView.
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: CompletionYearRoute.self) { CompletionYearView(year: $0.year) }
        }
    }
}

/// What you did, newest first.
struct JournalTimeline: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    /// Memories with no game — "first LAN party" — are reachable no other way.
    @Query(filter: #Predicate<Memory> { $0.deletedAt == nil && $0.game == nil })
    private var standaloneMemories: [Memory]

    /// The session being written about, if any.
    @State private var editing: Session?
    /// The memory being written or edited. `.some(nil)` means a new one, which
    /// is why this is a double optional rather than a Bool beside a Memory?.
    @State private var editingMemory: Memory??
    /// A picture being looked at full size.
    @State private var viewingImage: GameImage?

    var body: some View {
        // Built once per pass and held in a `let`, the same shape StatsCards
        // uses — as a computed property it would be rebuilt on every reference.
        let periods = JournalBuilder.periods(from: games, standalone: standaloneMemories)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(periods) { period in
                    VStack(alignment: .leading, spacing: 8) {
                        JournalPeriodHeader(period: period)
                        ForEach(period.entries) { entry in
                            JournalRow(entry: entry, editing: $editing,
                                       editingMemory: $editingMemory,
                                       viewingImage: $viewingImage)
                        }
                    }
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        // The existing editor, not a second one — it already writes notes,
        // and it knows that a paused session's editable end is not its stored
        // end, which a note-only sheet would have had to learn again.
        .sheet(item: $editing) { EditSessionSheet(session: $0) }
        .sheet(isPresented: Binding(
            get: { editingMemory != nil },
            set: { if !$0 { editingMemory = nil } })) {
            MemorySheet(existing: editingMemory ?? nil)
        }
        .sheet(item: $viewingImage) { LocalImageViewer(image: $0) }
        .toolbar {
            Button {
                editingMemory = .some(nil)
            } label: {
                Label("Add a memory", systemImage: "plus")
            }
        }
        .overlay {
            if periods.isEmpty {
                ContentUnavailableView(
                    "Nothing written down yet",
                    systemImage: "book.closed",
                    // Says what fills it, because an empty journal that does
                    // not is indistinguishable from a broken one.
                    description: Text("Time a session, finish a game, or log a run and it lands here — with whatever you wrote about it."))
            }
        }
    }
}

private struct JournalPeriodHeader: View {
    let period: JournalPeriod

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(period.title())
                .font(.headline)
            Spacer()
            // The count earns its place on a busy day and says nothing on a
            // quiet one, so it only appears when there is more than one thing.
            if period.entries.count > 1 {
                Text("\(period.entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry
    @Binding var editing: Session?
    @Binding var editingMemory: Memory??
    @Binding var viewingImage: GameImage?

    var body: some View {
        // **A memory row is a Button, not a NavigationLink.**
        //
        // It was a NavigationLink(value: entry.game), and a memory has no
        // game — a link with a nil value is DISABLED, so the whole row drew
        // greyed out. Tim: "it feels weird that it's greyed out like it's not
        // real or not accessible." It was not accessible; it was switched off.
        //
        // It also wants somewhere different to go. The subject of a memory row
        // is the memory, so tapping it opens the memory rather than whatever
        // game happens to be attached.
        Group {
            if let memory = entry.memory {
                Button { editingMemory = .some(memory) } label: { rowContent }
            } else {
                NavigationLink(value: entry.game) { rowContent }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let session = entry.session {
                Button {
                    editing = session
                } label: {
                    Label(entry.note == nil ? "Add a note" : "Edit note",
                          systemImage: "square.and.pencil")
                }
            }
            if let memory = entry.memory {
                Button {
                    editingMemory = .some(memory)
                } label: {
                    Label("Edit memory", systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// The row itself, so both the Button and the NavigationLink can wear it.
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
                if entry.kind == .memory {
                    // **A circle, not a cover-shaped rectangle.** A memory is
                    // not a game, and dressing it in box art said it was one
                    // that had simply failed to load its cover. Tim: "these
                    // memories/journal entries should have their own icon
                    // that's not in a game art frame." The column keeps its
                    // 44pt width so rows still line up.
                    Circle()
                        .fill(LSTheme.accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "sparkles")
                                .foregroundStyle(LSTheme.accent)
                        }
                } else if let game = entry.game {
                    CoverThumb(urlString: game.displayCoverURLString)
                        .frame(width: 44, height: 59)
                        .clipShape(.rect(cornerRadius: 6))
                        .coverGloss()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: entry.kind.icon)
                            .font(.caption2)
                        if let duration = entry.duration {
                            Text(Format.duration(duration))
                        } else if let detail = entry.detail {
                            Text(detail)
                        }
                        // Only a same-day entry gets a clock: printing 12:00
                        // under a heading that says "2011" would invent the
                        // precision the grain exists to withhold.
                        if entry.grain == .day {
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !entry.companions.isEmpty {
                        Label(entry.companions.map(\.name).joined(separator: ", "),
                              systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !entry.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(entry.images) { image in
                                    if let data = image.data {
                                        Button { viewingImage = image } label: {
                                            LocalArtworkThumb(data: data, contentMode: .fill)
                                                .frame(width: 72, height: 72)
                                                .clipShape(.rect(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Your words, given the weight of the row rather than a
                    // footnote's — this is the thing the surface exists for.
                    if let note = entry.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        .lsCard()
    }
}
