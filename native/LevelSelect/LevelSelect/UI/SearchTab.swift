import SwiftUI
import SwiftData

/// Universal search — opened from the magnifying glass on every tab, or ⌘F.
///
/// Designed on the canvas with Tim, 09-18
/// (https://claude.ai/artifact/8A4vB7j3YzQxYgTfkPE8Bw) as the tab bar's search
/// circle. Built, it turned out iOS draws that circle only beside four tabs —
/// five plus search folds Journal into "More" — and Tim chose a toolbar button
/// over merging tabs. Results are grouped by kind — your games, tracker items,
/// journal notes, news and releases — with IGDB last, so a game you don't have
/// is one tap from Add. Library and Wishlist keep their own search for
/// filtering within them.
struct SearchScreen: View {
    /// As the tab bar's search tab (four tabs) rather than a full-screen
    /// cover opened from a toolbar button (five).
    var inTab = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }) private var feeds: [NewsFeed]

    @State private var query = ""
    @State private var scope: UniversalSearch.Scope = .all
    @State private var path = NavigationPath()
    @State private var index = SearchIndex()
    @State private var results = SearchResults()
    @State private var igdb: [IGDBGame] = []
    @State private var igdbLoading = false
    @State private var adding: NamedAdd?
    @State private var release: UpcomingRelease?
    @State private var browsing: DekuLinkTarget?
    @State private var reader = GameNewsReader.shared
    @AppStorage("search.recent") private var recentRaw = ""

    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        // Always showing, tab or cover. `.automatic` in the tab tucked the
        // field away under the title until you pulled down — tapping Search
        // gave you recents and no field (King Kai, 09-18).
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private func takePendingTerm() {
        guard let term = AppNavigator.shared.pendingSearchTerm else { return }
        AppNavigator.shared.pendingSearchTerm = nil
        query = term
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trimmed.isEmpty {
                    emptyState
                } else {
                    scopeChips
                    resultSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .lsBackground()
            .navigationTitle("Search")
            // As a search-role tab the system puts the field in the tab bar
            // itself; as a cover it sits under the title, always showing.
            .searchable(text: $query, placement: searchPlacement, prompt: "Games, notes, trackers, news")
            .searchFocused($fieldFocused)
            .toolbar {
                if !inTab {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .onSubmit(of: .search) { remember() }
            .gamePageDestinations()
        }
        .task(id: games.count) { index = SearchIndex.build(games: games, context: context) }
        .onAppear {
            fieldFocused = true
            takePendingTerm()
        }
        // The tab stays alive after the first visit, so onAppear alone would
        // focus the field once. Every tap on Search is a request to type.
        .onChange(of: AppNavigator.shared.selectedTab) { _, tab in
            if inTab && tab == .search { fieldFocused = true }
        }
        .onChange(of: AppNavigator.shared.pendingSearchTerm) { _, _ in takePendingTerm() }
        // Opening anything from results is what makes a search worth
        // remembering. This used to be a tap gesture on each game row, and on
        // iOS 27 that gesture swallowed the row's own navigation: tapping
        // Super Metroid in results did nothing (simulator, 09-18).
        .onChange(of: path.count) { old, new in if new > old, !trimmed.isEmpty { remember() } }
        .task(id: "\(trimmed)|\(scope.rawValue)|\(index.version)") { await search() }
        .sheet(item: $adding) { target in
            AddGameSheet(initialSearch: target.name).lsSheet()
        }
        .sheet(item: $release) { r in
            UpcomingDetailSheet(release: r, games: games).lsSheet([.large])
        }
        .newsBrowser(target: $browsing)
    }

    // MARK: Before typing

    @ViewBuilder
    private var emptyState: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { term in
                    Button { query = term } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                    .listRowBackground(Color.clear)
                }
                Button("Clear Recent Searches") { recentRaw = "" }
                    .font(.footnote)
                    .listRowBackground(Color.clear)
            } header: {
                Text("Recent")
            }
        }
        let playing = games.filter { $0.status == .playing }
            .sorted { ($0.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? $0.addedAt)
                    > ($1.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? $1.addedAt) }
            .prefix(4)
        if !playing.isEmpty {
            Section("Jump back in") {
                ForEach(Array(playing)) { game in
                    NavigationLink(value: game) { GameRow(game: game) }
                        .listRowBackground(Color.clear)
                }
            }
        }
        if recent.isEmpty && playing.isEmpty {
            Section {
                Text("Search your games, tracker items, journal notes, news and upcoming releases — and IGDB, for a game you don't have yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: Results

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(UniversalSearch.Scope.allCases) { s in
                    let on = s == scope
                    Button { scope = s } label: {
                        Text(s.label)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(on ? LSTheme.onAccent : .primary)
                            .background(on ? AnyShapeStyle(LSTheme.accentFill) : AnyShapeStyle(.quaternary), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// In All, three of each and a way to see the rest.
    private func cap<T>(_ list: [T]) -> [T] { scope == .all ? Array(list.prefix(3)) : list }

    @ViewBuilder
    private var resultSections: some View {
        if results.isEmpty && igdb.isEmpty && !igdbLoading {
            Section {
                ContentUnavailableView.search(text: trimmed)
                    .listRowBackground(Color.clear)
            }
        }
        if !results.games.isEmpty {
            Section {
                ForEach(cap(results.games)) { game in
                    NavigationLink(value: game) { GameRow(game: game) }
                        .listRowBackground(Color.clear)
                }
            } header: { header("Your games", results.games.count, .games) }
        }
        if !results.trackers.isEmpty {
            Section {
                ForEach(cap(results.trackers)) { hit in
                    resultLine(icon: hit.done ? "checkmark.square.fill" : "square",
                               title: hit.item + (hit.done ? " — done" : ""),
                               sub: "\(hit.gameName) · \(hit.category)") {
                        open(gameID: hit.gameID)
                    }
                }
            } header: { header("Trackers", results.trackers.count, .trackers) }
        }
        if !results.notes.isEmpty {
            Section {
                ForEach(cap(results.notes)) { note in
                    resultLine(icon: note.icon,
                               title: "“" + UniversalSearch.snippet(note.text, trimmed) + "”",
                               sub: note.source) {
                        if let id = note.gameID { open(gameID: id) }
                    }
                }
            } header: { header("Journal", results.notes.count, .journal) }
        }
        if !results.stories.isEmpty || !results.releases.isEmpty {
            Section {
                ForEach(cap(results.releases)) { r in
                    resultLine(icon: "calendar", title: r.name, sub: releaseLine(r)) {
                        remember()
                        release = r
                    }
                }
                ForEach(cap(results.stories)) { s in
                    resultLine(icon: "newspaper", title: s.title,
                               sub: feeds.first { $0.id == s.feedID }?.title ?? "News") {
                        remember()
                        Repository(context).markRead(s)
                        if let link = s.link { browsing = DekuLinkTarget(url: link) }
                    }
                }
            } header: { header("News & releases", results.stories.count + results.releases.count, .news) }
        }
        if scope == .all || scope == .games {
            if igdbLoading && igdb.isEmpty {
                Section("Add from IGDB") {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            } else if !igdb.isEmpty {
                Section("Add from IGDB") {
                    ForEach(igdb.prefix(5)) { g in
                        HStack(spacing: 12) {
                            CoverThumb(urlString: g.coverURLString, artwork: nil, name: g.name, status: .wishlist)
                                .frame(width: 34, height: 45)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).lineLimit(2)
                                Text([g.releaseYear.map(String.init), g.developers.first].compactMap { $0 }
                                    .joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                remember()
                                adding = NamedAdd(name: g.name)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .background(.quaternary, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(LSTheme.accent)
                            .accessibilityLabel("Add \(g.name)")
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
    }

    private func header(_ title: String, _ count: Int, _ kind: UniversalSearch.Scope) -> some View {
        HStack {
            Text(title)
            Spacer()
            if scope == .all && count > 3 {
                Button("See all \(count)") { scope = kind }
                    .font(.footnote)
                    .textCase(nil)
            }
        }
    }

    private func resultLine(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).lineLimit(3)
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func releaseLine(_ r: UpcomingRelease) -> String {
        let start = UpcomingReleases.utc.startOfDay(for: .now)
        if let n = r.next(on: Set(r.rows.map(\.platform)), from: start) {
            let when = n.precision.hasDay
                ? NewsUpcomingView.utcDate(n.date) { $0.month(.abbreviated).day() }
                : NewsUpcomingView.utcDate(n.date) { $0.year() }
            return "Out \(when) · " + n.platforms.prefix(3).joined(separator: " · ")
        }
        return "Out now"
    }

    private func open(gameID: UUID) {
        remember()
        if let game = games.first(where: { $0.id == gameID }) { path.append(game) }
    }

    private func remember() {
        let next = UniversalSearch.remember(trimmed, in: recent)
        recentRaw = next.joined(separator: "\n")
    }

    // MARK: Searching

    private func search() async {
        let q = trimmed
        guard !q.isEmpty else {
            results = SearchResults()
            igdb = []
            return
        }
        // Let typing settle.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        results = SearchResults.find(q, scope: scope, games: games, index: index,
                                     stories: reader.stories, releases: reader.upcoming)
        guard scope == .all || scope == .games, q.count >= 3 else {
            igdb = []
            return
        }
        igdbLoading = true
        defer { igdbLoading = false }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        let have = Set(games.compactMap(\.igdbID))
        var found = (try? await IGDBService.search(name: q)) ?? []
        if found.isEmpty, let joined = UniversalSearch.runTogether(q) {
            found = (try? await IGDBService.search(name: joined)) ?? []
        }
        guard !Task.isCancelled else { return }
        igdb = found.filter { !have.contains($0.id) }
    }
}

/// The magnifying glass on every tab's toolbar.
struct SearchButton: View {
    var body: some View {
        Button { AppNavigator.shared.searchPresented = true } label: {
            Label("Search", systemImage: "magnifyingglass")
                .foregroundStyle(LSTheme.accent)
        }
    }
}

private struct NamedAdd: Identifiable {
    let name: String
    var id: String { name }
}

// MARK: - Index

/// What search matches against beyond game names: every tracker item, and
/// every note you've written. Built when the tab opens and when the library
/// changes size — decoding every tracker on each keystroke would be the slow
/// way round.
struct SearchIndex {
    struct TrackerHit: Identifiable, Hashable {
        let gameID: UUID
        let gameName: String
        let itemID: String
        let item: String
        let category: String
        let done: Bool
        var id: String { "\(gameID)|\(itemID)" }
    }

    struct Note: Identifiable, Hashable {
        let id: String
        let gameID: UUID?
        let icon: String
        let text: String
        let source: String
        let date: Date
    }

    var trackers: [TrackerHit] = []
    var notes: [Note] = []
    var version = 0

    @MainActor
    static func build(games: [Game], context: ModelContext) -> SearchIndex {
        var out = SearchIndex()
        out.version = Int(Date.now.timeIntervalSince1970)
        for game in games {
            if let schema = game.trackerSchema {
                let done = Set((game.activePlaythrough?.trackerStates ?? [])
                    .filter { $0.deletedAt == nil && $0.completed }.map(\.itemID))
                for cat in TrackerSchemaJSON.categories(from: schema.jsonData) {
                    for item in cat.items where !item.name.isEmpty {
                        out.trackers.append(TrackerHit(gameID: game.id, gameName: game.name, itemID: item.id,
                                                       item: item.name, category: cat.name,
                                                       done: done.contains(item.id)))
                    }
                }
            }
            let notes = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                out.notes.append(Note(id: "g\(game.id)", gameID: game.id, icon: "note.text", text: notes,
                                      source: "Notes · \(game.name)", date: game.updatedAt))
            }
            if let review = game.review?.trimmingCharacters(in: .whitespacesAndNewlines), !review.isEmpty {
                out.notes.append(Note(id: "r\(game.id)", gameID: game.id, icon: "star.bubble", text: review,
                                      source: "Review · \(game.name)", date: game.updatedAt))
            }
            for p in game.livePlaythroughs {
                if let n = p.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    out.notes.append(Note(id: "p\(p.id)", gameID: game.id, icon: "flag", text: n,
                                          source: "\(p.name.isEmpty ? "Playthrough" : p.name) · \(game.name)",
                                          date: p.updatedAt))
                }
                for s in p.sessions ?? [] where s.deletedAt == nil {
                    guard let n = s.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { continue }
                    out.notes.append(Note(id: "s\(s.id)", gameID: game.id, icon: "pencil", text: n,
                                          source: "Session note · \(game.name) · \(s.startDate.formatted(.dateTime.month(.abbreviated).day()))",
                                          date: s.startDate))
                }
            }
        }
        let memories = ((try? context.fetch(FetchDescriptor<Memory>())) ?? []).filter { $0.deletedAt == nil }
        for m in memories {
            let text = [m.title, m.body ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
            guard !text.isEmpty else { continue }
            out.notes.append(Note(id: "m\(m.id)", gameID: m.game?.id, icon: "sparkles", text: text,
                                  source: "Memory" + (m.game.map { " · \($0.name)" } ?? ""), date: m.latest))
        }
        out.notes.sort { $0.date > $1.date }
        return out
    }
}

struct SearchResults {
    var games: [Game] = []
    var trackers: [SearchIndex.TrackerHit] = []
    var notes: [SearchIndex.Note] = []
    var stories: [FeedStory] = []
    var releases: [UpcomingRelease] = []

    var isEmpty: Bool { games.isEmpty && trackers.isEmpty && notes.isEmpty && stories.isEmpty && releases.isEmpty }

    static func find(_ q: String, scope: UniversalSearch.Scope, games: [Game], index: SearchIndex,
                     stories: [FeedStory], releases: [UpcomingRelease]) -> SearchResults {
        var r = SearchResults()
        let want = { (s: UniversalSearch.Scope) in scope == .all || scope == s }
        if want(.games) {
            r.games = games.filter { UniversalSearch.matches($0.name + " " + ($0.franchise ?? ""), q) }
                .sorted { (UniversalSearch.rank($0.name, q), $0.name) < (UniversalSearch.rank($1.name, q), $1.name) }
        }
        if want(.trackers) {
            r.trackers = Array(index.trackers.filter { UniversalSearch.matches($0.item, q) }
                .sorted { (UniversalSearch.rank($0.item, q), $0.item) < (UniversalSearch.rank($1.item, q), $1.item) }
                .prefix(200))
        }
        if want(.journal) {
            r.notes = Array(index.notes.filter { UniversalSearch.matches($0.text, q) }.prefix(200))
        }
        if want(.news) {
            r.stories = Array(stories.filter { UniversalSearch.matches($0.title, q) }.prefix(100))
            r.releases = Array(releases.filter { UniversalSearch.matches($0.name, q) }
                .sorted { UniversalSearch.rank($0.name, q) < UniversalSearch.rank($1.name, q) }
                .prefix(50))
        }
        return r
    }
}

/// Library's two halves, one tab. See `LSTab.wishlistInLibrary`.
struct LibraryHalves: View {
    @State private var nav = AppNavigator.shared

    var body: some View {
        switch nav.libraryHalf {
        case .collection: LibraryTab()
        case .wishlist: WishlistTab()
        }
    }
}

/// Collection | Wishlist, at the top of both halves.
struct LibraryHalfPicker: View {
    @State private var nav = AppNavigator.shared

    var body: some View {
        Picker("Library", selection: Binding(get: { nav.libraryHalf }, set: { nav.libraryHalf = $0 })) {
            ForEach(LibraryHalf.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

extension View {
    /// What a game page links onward to — its tracker, a genre or studio, its
    /// system, a collection. Every tab that can show a game page has to
    /// register these on its own stack; Search and News (build 39) only
    /// registered `Game`, so a tracker's Open, a genre chip or a system chip
    /// on a page reached from them did nothing (simulator, 09-18).
    func gamePageDestinations() -> some View {
        self
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: PlatformRoute.self) {
                PlatformGamesView(platform: $0.platform, ownership: $0.ownership)
            }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: CollectionRoute.self) { CollectionRouteView(route: $0) }
    }
}
