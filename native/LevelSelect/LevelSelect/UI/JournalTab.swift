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
        /// Three readings of one record set: what happened in order, what
        /// happened when, and what it all adds up to. The calendar sits in the
        /// middle because it is the bridge — a shape you scan rather than
        /// read, and a way into any day.
        case timeline, calendar, charts
        var id: String { rawValue }
        var label: String {
            switch self {
            case .timeline: "Timeline"
            case .calendar: "Calendar"
            case .charts:   "Charts"
            }
        }
        var icon: String {
            switch self {
            case .timeline: "list.bullet.indent"
            case .calendar: "calendar"
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
                case .calendar: JournalCalendarView()
                case .charts:   StatsCards()
                }
            }
            .lsBackground()
            .navigationTitle("Journal")
            // Glass, like Home — see LibraryView.
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .navigationDestination(for: JournalRoute.self) { JournalRouteDestination(route: $0) }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: CompletionYearRoute.self) { CompletionYearView(year: $0.year) }
        }
    }
}

/// Resolves a `JournalRoute` to the thing it names.
///
/// **A view with its own queries, rather than a closure inside one lens.** It
/// used to live in `JournalTimeline`, on the reasoning that that was where the
/// data was — but a destination is only registered while the view declaring it
/// is on screen, so adding the calendar lens gave it rows that looked tappable
/// and did nothing. Registered beside the other destinations on the stack that
/// owns them, every lens can navigate.
///
/// A route carries ids, not objects: `JournalEntry` holds live SwiftData
/// references and is rebuilt every pass, which makes it the wrong thing to
/// hand a navigation path.
private struct JournalRouteDestination: View {
    let route: JournalRoute

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    @Query(filter: #Predicate<Memory> { $0.deletedAt == nil && $0.game == nil })
    private var standaloneMemories: [Memory]

    private var memory: Memory? {
        let all = standaloneMemories + games.flatMap { $0.memories ?? [] }
        return all.first { $0.id.uuidString == route.id && $0.deletedAt == nil }
    }

    private var playEntry: JournalEntry? {
        guard let gameID = route.gameID,
              let game = games.first(where: { $0.id == gameID })
        else { return nil }
        return JournalBuilder.playEntries(for: game).first { $0.id == route.id }
    }

    var body: some View {
        if route.isMemory {
            if let memory {
                MemoryView(memory: memory)
            } else {
                ContentUnavailableView("Gone", systemImage: "questionmark",
                                       description: Text("This entry no longer exists."))
            }
        } else if let playEntry {
            JournalDayView(entry: playEntry)
        } else {
            ContentUnavailableView("Gone", systemImage: "questionmark",
                                   description: Text("This day no longer has anything in it."))
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
                                       editingMemory: $editingMemory)
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

    var body: some View {
        // **Tap reads, long-press edits.** They were the same gesture, so
        // opening a row to see what you wrote put you in an editor instead.
        // Tim: "tapping to view a full journal entry, and pressing to edit
        // should be different actions."
        NavigationLink(value: JournalRoute(entry: entry)) { rowContent }
            .buttonStyle(.plain)
            .contextMenu {
                if let memory = entry.memory {
                    Button { editingMemory = .some(memory) } label: {
                        Label("Edit memory", systemImage: "square.and.pencil")
                    }
                } else if entry.sessions.count == 1, let only = entry.sessions.first {
                    // One session is unambiguous, so the shortcut is safe.
                    // With several, "edit note" would have to ask which — the
                    // day view is where that choice belongs.
                    Button { editing = only } label: {
                        Label(only.notes?.journalText == nil ? "Add a note" : "Edit note",
                              systemImage: "square.and.pencil")
                    }
                }
                if let game = entry.game {
                    NavigationLink(value: game) {
                        Label("Go to \(game.name)", systemImage: "gamecontroller")
                    }
                }
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if entry.kind == .memory {
                // A circle, not box art: a memory is not a game, and a
                // cover-shaped frame said it was one whose art failed to load.
                Circle()
                    .fill(LSTheme.accent.opacity(0.16))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "sparkles").foregroundStyle(LSTheme.accent)
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

                summary

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
                                    LocalArtworkThumb(data: data, contentMode: .fill)
                                        .frame(width: 72, height: 72)
                                        .clipShape(.rect(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // Your words. Several notes on one day are several lines —
                // the day summary above says how much you played, this says
                // what you said about it.
                ForEach(Array(entry.notes.prefix(3).enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .padding(.top, 2)
                }
                if entry.notes.count > 3 {
                    Text("+ \(entry.notes.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .lsCard()
    }

    /// One line saying what the day amounted to.
    @ViewBuilder
    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind.icon).font(.caption2)
            if entry.kind == .memory {
                if let detail = entry.detail { Text(detail) }
            } else {
                if entry.duration > 0 {
                    Text(Format.duration(entry.duration))
                }
                if entry.sessions.count > 1 {
                    Text("· \(entry.sessions.count) sessions")
                }
                if !entry.runs.isEmpty {
                    Text("· \(entry.runs.count) " + (entry.runs.count == 1 ? "run" : "runs"))
                }
                ForEach(entry.finishes) { finish in
                    Label(finish.journalLabel, systemImage: "flag.checkered")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(LSTheme.accent)
                }
            }
            if entry.grain == .day, entry.kind == .memory {
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Where a journal row goes when tapped.
///
/// A value rather than the entry itself: `JournalEntry` holds live SwiftData
/// objects and is rebuilt every pass, so it is the wrong thing to put in a
/// navigation path. This carries only what the destination needs to find it
/// again.
struct JournalRoute: Hashable {
    let id: String
    let isMemory: Bool
    let gameID: UUID?
    let day: Date

    init(entry: JournalEntry) {
        id = entry.id
        isMemory = entry.kind == .memory
        gameID = entry.game?.id
        day = entry.date
    }
}
