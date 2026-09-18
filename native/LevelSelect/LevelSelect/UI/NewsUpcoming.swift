import SwiftUI
import SwiftData

/// News → New & Upcoming: what just came out and what comes out next, on the
/// systems you care about.
///
/// Tim, 09-18, after setting it beside Game Informer's list: missing games
/// (fixed in `UpcomingRelease` — ports and late platforms now count), *"I
/// should be able to turn off certain systems from showing in the upcoming
/// games 'your systems', like PC, since I haven't gamed on PC for 20 years, and
/// I have a Mac now"*, and a way to tap into a game — *"just info, news
/// stories, and maybe trailers if they exist"*, not a full game page.
struct NewsUpcomingView: View {
    let games: [Game]
    let consoles: [Console]
    let addToWishlist: (String) -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all, yourSystems, wishlist
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All releases"
            case .yourSystems: "Your systems"
            case .wishlist: "Wishlist"
            }
        }
    }

    @State private var reader = GameNewsReader.shared
    @AppStorage("news.upcomingFilter") private var filterRaw = Filter.all.rawValue
    /// The systems "Your systems" means, comma-separated. Empty until you
    /// choose, which means the consoles you own.
    @AppStorage(SuggestionPrefs.upcomingSystemsKey) private var systemsRaw = ""
    @State private var choosingSystems = false
    @State private var showingLater = false
    @State private var showingAllJustOut = false
    @State private var detail: UpcomingRelease?

    private var filter: Filter { Filter(rawValue: filterRaw) ?? .all }
    private var start: Date { UpcomingReleases.utc.startOfDay(for: .now) }

    private var owned: Set<String> {
        Set(consoles.map { PlatformKey.canonical($0.platform) }.filter { !$0.isEmpty && $0 != "Other" })
    }

    /// Chosen, or — until you choose — the consoles you own.
    private var yourSystems: Set<String> {
        let chosen = Set(systemsRaw.split(separator: ",").map(String.init))
        return chosen.isEmpty ? owned : chosen
    }

    private var wishlistIDs: Set<Int> { Set(games.filter { $0.status == .wishlist }.compactMap(\.igdbID)) }
    private var ownedIDs: Set<Int> { Set(games.filter { $0.status != .wishlist }.compactMap(\.igdbID)) }

    private var allowed: Set<String> {
        switch filter {
        case .all: UpcomingReleases.mainPlatforms.union(yourSystems)
        case .yourSystems: yourSystems
        case .wishlist: Set(reader.upcoming.flatMap { $0.rows.map(\.platform) })
        }
    }

    private var releases: [UpcomingRelease] {
        filter == .wishlist ? reader.upcoming.filter { wishlistIDs.contains($0.id) } : reader.upcoming
    }

    private var sections: [UpcomingReleases.Section] {
        UpcomingReleases.sections(releases, allowed: allowed, from: start)
    }

    /// The most-followed of the next month, in date order. Filtered views
    /// fall back to the soonest, since your wishlist is its own shortlist.
    private func upNext(_ sections: [UpcomingReleases.Section]) -> [(release: UpcomingRelease, next: UpcomingRelease.Next)] {
        let dated = sections.filter { $0.month != nil }.flatMap(\.items).filter { $0.next.precision.hasDay }
        let soon = dated.filter { $0.next.date < start.addingTimeInterval(31 * 86_400) }
        if filter != .wishlist {
            let rank = Dictionary(uniqueKeysWithValues: reader.upNextIDs.enumerated().map { ($1, $0) })
            let picked = soon.filter { rank[$0.release.id] != nil }
                .sorted { rank[$0.release.id]! < rank[$1.release.id]! }
                .prefix(10)
                .sorted { $0.next.date < $1.next.date }
            if !picked.isEmpty { return Array(picked) }
        }
        return Array(dated.prefix(10))
    }

    var body: some View {
        let sections = self.sections
        let justOut = UpcomingReleases.justOut(releases, allowed: allowed, today: start)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterChips
                if reader.upcoming.isEmpty {
                    if reader.upcomingFailed {
                        ContentUnavailableView("Couldn't load releases", systemImage: "calendar.badge.exclamationmark",
                                               description: Text("Pull down to try again."))
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                } else if sections.isEmpty && justOut.isEmpty {
                    Text(filter == .wishlist ? "Nothing on your wishlist is dated in the next six months."
                                             : "Nothing coming to your systems in the next six months.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    let next = upNext(sections)
                    if !next.isEmpty {
                        Text("Up next").font(.title3.weight(.semibold)).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(next, id: \.release.id) { item in
                                    Button { detail = item.release } label: { upNextCard(item.release, item.next) }
                                        .buttonStyle(PressableCardStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    if !justOut.isEmpty { justOutSection(justOut) }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    Text("Games people are following or rating on IGDB, on every platform they launch on — a port counts. Up Next is the month's most-followed; Just Out is the last two weeks. Dates are what publishers have announced, and they move.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await reader.loadUpcoming(force: true) }
        .task { await reader.loadUpcoming() }
        .sheet(isPresented: $choosingSystems) {
            UpcomingSystemsSheet(owned: owned, systemsRaw: $systemsRaw).lsSheet([.medium, .large])
        }
        .sheet(item: $detail) { release in
            UpcomingDetailSheet(release: release, games: games).lsSheet([.large])
        }
    }

    // MARK: Pieces

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { f in
                let on = f == filter
                Button { filterRaw = f.rawValue } label: {
                    Text(f.label)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary)))
                        .foregroundStyle(on ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button { choosingSystems = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LSTheme.accent)
            .lsTapTargetTall(8)
            .accessibilityLabel("Choose your systems")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func sectionView(_ section: UpcomingReleases.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let month = section.month {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.utcDate(month) { $0.month(.wide).year() })
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(section.items.count) \(section.items.count == 1 ? "game" : "games")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                ForEach(section.items, id: \.release.id) { row($0.release, $0.next) }
            } else {
                // Year- and quarter-only dates, folded: IGDB pads "2026" to
                // 31 December, so these would otherwise read as one enormous
                // December.
                Button { withAnimation { showingLater.toggle() } } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Later — no exact date").font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(section.items.count) games").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(showingLater ? 0 : -90))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                if showingLater {
                    ForEach(section.items, id: \.release.id) { row($0.release, $0.next) }
                }
            }
        }
        .padding(.horizontal)
    }

    /// Eight of them: the most-followed, newest first — or simply the newest
    /// eight when IGDB named none, or on the wishlist filter.
    private func shortList(_ items: [(release: UpcomingRelease, next: UpcomingRelease.Next)])
        -> [(release: UpcomingRelease, next: UpcomingRelease.Next)] {
        let top = Set(reader.justOutIDs)
        let picked = filter == .wishlist ? [] : items.filter { top.contains($0.release.id) }
        return Array((picked.isEmpty ? items : picked).prefix(8))
    }

    /// Out in the last two weeks — a game you might otherwise have missed
    /// (Tim, 09-18). The most-followed eight, then Show All, newest first.
    private func justOutSection(_ items: [(release: UpcomingRelease, next: UpcomingRelease.Next)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Just out").font(.title3.weight(.semibold))
                Spacer()
                Text("Last \(UpcomingReleases.justOutDays) days").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            ForEach(showingAllJustOut ? items : shortList(items), id: \.release.id) {
                row($0.release, $0.next, justOut: true)
            }
            if items.count > shortList(items).count {
                Button(showingAllJustOut ? "Show fewer" : "Show all \(items.count)") {
                    withAnimation { showingAllJustOut.toggle() }
                }
                .font(.subheadline)
                .padding(.top, 10)
            }
        }
        .padding(.horizontal)
    }

    static func utcDate(_ date: Date, _ style: (Date.FormatStyle) -> Date.FormatStyle) -> String {
        var f = Date.FormatStyle.dateTime
        f.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style(f))
    }

    static func ago(_ date: Date, today: Date) -> String {
        let d = UpcomingReleases.utc.dateComponents([.day], from: date, to: today).day ?? 0
        return d <= 1 ? "out yesterday" : "out \(d) days ago"
    }

    private func days(until date: Date) -> Int {
        UpcomingReleases.utc.dateComponents([.day], from: start, to: date).day ?? 0
    }

    private func upNextCard(_ r: UpcomingRelease, _ n: UpcomingRelease.Next) -> some View {
        let d = days(until: n.date)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: r.coverURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { LSTheme.accent.opacity(0.15) }
                }
                .frame(width: 150, height: 190)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d <= 0 ? "Today" : "\(d)")
                        .font(.system(size: d <= 0 ? 26 : 34, weight: .semibold))
                    if d > 0 {
                        Text("\(d == 1 ? "day" : "days") · \(Self.utcDate(n.date) { $0.weekday(.abbreviated).month(.abbreviated).day() })")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            // The gradient is greedy; without this the card grew a blank band.
            .frame(width: 150, height: 190)
            .clipped()
            .overlay(alignment: .topTrailing) { mark(r).padding(8) }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.footnote).lineLimit(2).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(n.platforms.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
        }
        .frame(width: 150, alignment: .leading)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func mark(_ r: UpcomingRelease) -> some View {
        if wishlistIDs.contains(r.id) {
            UpcomingBadge(text: "Wishlist")
        } else if ownedIDs.contains(r.id) {
            UpcomingBadge(text: "In library")
        }
    }

    private func row(_ r: UpcomingRelease, _ n: UpcomingRelease.Next, justOut: Bool = false) -> some View {
        // For a new release, "out now on" is the other platforms it was
        // already on before this launch.
        let out = r.alreadyOut(before: justOut ? n.date : start)
        return HStack(spacing: 12) {
            Button { detail = r } label: {
                HStack(spacing: 12) {
                    UpcomingDateBlock(next: n)
                        .frame(width: 44)
                    AsyncImage(url: r.coverURL) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.15) }
                    }
                    .frame(width: 36, height: 48)
                    .clipShape(.rect(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.subheadline).lineLimit(2).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(n.platforms.joined(separator: " · ")
                             + (justOut ? " · " + Self.ago(n.date, today: start) : ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !out.isEmpty {
                            Text("Out now on \(Array(Set(out.map(\.platform))).sorted().joined(separator: " · "))")
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if wishlistIDs.contains(r.id) || ownedIDs.contains(r.id) {
                mark(r)
            } else {
                Button { addToWishlist(r.name) } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: .circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LSTheme.accent)
                .accessibilityLabel("Add \(r.name) to wishlist")
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(.quaternary.opacity(0.6)).frame(height: 1) }
    }
}

struct UpcomingBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(LSTheme.onAccent)
            .background(LSTheme.accentFill, in: .capsule)
    }
}

/// The day and weekday when IGDB knows the day; otherwise what it does know.
struct UpcomingDateBlock: View {
    let next: UpcomingRelease.Next

    var body: some View {
        VStack(spacing: 2) {
            switch next.precision {
            case .day:
                Text(NewsUpcomingView.utcDate(next.date) { $0.day() }).font(.title3.weight(.medium))
                Text(NewsUpcomingView.utcDate(next.date) { $0.weekday(.abbreviated) }.uppercased())
                    .font(.caption2).foregroundStyle(.secondary)
            case .month:
                Text(NewsUpcomingView.utcDate(next.date) { $0.month(.abbreviated) }.uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("TBC").font(.caption2).foregroundStyle(.tertiary)
            case .quarter:
                let m = UpcomingReleases.utc.component(.month, from: next.date)
                Text("Q\((m - 1) / 3 + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(NewsUpcomingView.utcDate(next.date) { $0.year() }).font(.caption2).foregroundStyle(.tertiary)
            case .year:
                Text(NewsUpcomingView.utcDate(next.date) { $0.year() }).font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .tbd, .unknown:
                Text("TBA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Systems

/// Which systems "Your systems" means. Starts as the consoles you own; Tim
/// turns PC off and Mac on.
struct UpcomingSystemsSheet: View {
    let owned: Set<String>
    @Binding var systemsRaw: String
    @Environment(\.dismiss) private var dismiss

    private var chosen: Set<String> {
        let c = Set(systemsRaw.split(separator: ",").map(String.init))
        return c.isEmpty ? owned : c
    }

    private var yours: [String] {
        owned.sorted { a, b in
            let ia = UpcomingReleases.pickable.firstIndex(of: a) ?? 99
            let ib = UpcomingReleases.pickable.firstIndex(of: b) ?? 99
            return (ia, a) < (ib, b)
        }
    }

    private var others: [String] { UpcomingReleases.pickable.filter { !owned.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                if !yours.isEmpty {
                    Section {
                        ForEach(yours, id: \.self) { toggle($0) }
                    } header: {
                        Text("Your consoles")
                    } footer: {
                        Text("Switch one off to keep its releases out of Your Systems.")
                    }
                }
                Section("More systems") {
                    ForEach(others, id: \.self) { toggle($0) }
                }
            }
            .navigationTitle("Your Systems")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        systemsRaw = ""
                        SuggestionPrefs.changed()
                    }
                    .disabled(systemsRaw.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func toggle(_ system: String) -> some View {
        Toggle(system, isOn: Binding(
            get: { chosen.contains(system) },
            set: { on in
                var set = chosen
                if on { set.insert(system) } else { set.remove(system) }
                // Never store an empty choice: empty means "my consoles".
                systemsRaw = set.isEmpty ? "" : set.sorted().joined(separator: ",")
                // Synced with your follows and hides (`SuggestionPrefs`).
                SuggestionPrefs.changed()
            }))
        .tint(LSTheme.accent)
    }
}

// MARK: - Detail

/// One upcoming game: when and where it lands, what it is, its trailers, and
/// the news about it. Deliberately not a game page — Tim: *"They shouldn't be
/// full game pages though, just info, news stories, and maybe trailers."*
struct UpcomingDetailSheet: View {
    let release: UpcomingRelease
    let games: [Game]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }) private var feeds: [NewsFeed]
    @Query(filter: #Predicate<NewsItemState> { $0.deletedAt == nil }) private var states: [NewsItemState]
    @State private var reader = GameNewsReader.shared
    @State private var heroImageID: String?
    @State private var playing: String?
    @State private var adding = false
    @State private var browsing: DekuLinkTarget?

    private var start: Date { UpcomingReleases.utc.startOfDay(for: .now) }

    private var libraryGame: Game? { games.first { $0.igdbID == release.id } }

    private var stories: [FeedStory] {
        let matcher = GameNewsMatcher(games: [(UUID(), release.name, "wishlist")])
        let on = Set(feeds.filter { !$0.muted }.map(\.id))
        return reader.stories.filter { on.contains($0.feedID) && !matcher.games(in: $0).isEmpty }
    }

    private var env: NewsEnv {
        NewsEnv.make(feeds: feeds, states: states, context: context, reader: reader) { url in
            #if os(iOS)
            browsing = DekuLinkTarget(url: url)
            #else
            openURL(url)
            #endif
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    status
                    whenAndWhere
                    if let summary = release.summary, !summary.isEmpty {
                        Text(summary).font(.body).foregroundStyle(.secondary)
                    }
                    info
                    trailers
                    news
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .lsBackground()
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await loadHero() }
        .sheet(isPresented: $adding) {
            AddGameSheet(initialSearch: release.name, defaultStatus: .wishlist).lsSheet()
        }
        #if os(iOS)
        .newsBrowser(target: $browsing)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .overlay {
                    AsyncImage(url: heroImageID.flatMap {
                        URL(string: "https://images.igdb.com/igdb/image/upload/t_screenshot_big/\($0).jpg")
                    }) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { LSTheme.accent.opacity(0.12) }
                    }
                }
                .clipShape(.rect(cornerRadius: 16))
                .overlay(alignment: .bottomLeading) {
                    AsyncImage(url: release.coverURL) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.2) }
                    }
                    .frame(width: 84, height: 112)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)))
                    .shadow(radius: 8)
                    .offset(x: 12, y: 40)
                }
            VStack(alignment: .leading, spacing: 4) {
                if let genre = release.genres.first {
                    Text(genre.uppercased())
                        .font(.caption.weight(.semibold)).kerning(0.6)
                        .foregroundStyle(LSTheme.accent)
                }
                Text(release.name).font(.title2.weight(.bold))
            }
            .padding(.leading, 108)
            .padding(.top, 8)
            .frame(minHeight: 56, alignment: .top)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var status: some View {
        if let game = libraryGame {
            Label(game.status == .wishlist ? "On your wishlist" : "In your library",
                  systemImage: game.status == .wishlist ? "bag.fill" : "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LSTheme.accent)
        } else {
            Button { adding = true } label: {
                Label("Add to Wishlist", systemImage: "bag.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(LSTheme.accentFill)
        }
    }

    /// Every platform's date — "May 22 (PS5, Xbox Series, PC) · Sep 18 (Switch 2)".
    private var whenAndWhere: some View {
        let grouped = Dictionary(grouping: release.rows) { row -> String in
            row.precision.hasDay ? NewsUpcomingView.utcDate(row.date) { $0.month(.abbreviated).day().year() }
                                 : label(for: row)
        }
        let ordered = grouped.sorted { ($0.value.map(\.date).min() ?? .distantFuture) < ($1.value.map(\.date).min() ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Release").font(.headline)
            ForEach(ordered, id: \.key) { when, rows in
                let isOut = rows.allSatisfy { $0.date < start && $0.precision.hasDay }
                HStack(alignment: .firstTextBaseline) {
                    Text(when).font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOut ? .secondary : .primary)
                    Spacer()
                    Text(rows.map(\.platform).sorted().joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if isOut {
                    Text("Out now").font(.caption2).foregroundStyle(.tertiary)
                } else if let first = rows.first, first.precision.hasDay {
                    let d = UpcomingReleases.utc.dateComponents([.day], from: start, to: first.date).day ?? 0
                    Text(d == 0 ? "Out today" : d == 1 ? "Tomorrow" : "In \(d) days")
                        .font(.caption2).foregroundStyle(LSTheme.accent)
                }
            }
        }
        .lsCard()
    }

    private func label(for row: UpcomingRelease.Row) -> String {
        switch row.precision {
        case .month: NewsUpcomingView.utcDate(row.date) { $0.month(.wide).year() }
        case .quarter:
            "Q\((UpcomingReleases.utc.component(.month, from: row.date) - 1) / 3 + 1) "
                + NewsUpcomingView.utcDate(row.date) { $0.year() }
        case .year: NewsUpcomingView.utcDate(row.date) { $0.year() }
        default: "To be announced"
        }
    }

    @ViewBuilder
    private var info: some View {
        let lines: [(String, String)] = [
            ("Developer", release.developers.joined(separator: ", ")),
            ("Publisher", release.publishers.joined(separator: ", ")),
            ("Genre", release.genres.joined(separator: ", ")),
        ].filter { !$0.1.isEmpty }
        if !lines.isEmpty {
            VStack(spacing: 0) {
                ForEach(lines, id: \.0) { key, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(key.uppercased()).font(.caption.weight(.semibold)).kerning(0.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(value).font(.subheadline).multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 9)
                    if key != lines.last?.0 { Divider() }
                }
            }
            .lsCard()
        }
    }

    @ViewBuilder
    private var trailers: some View {
        if !release.videoIDs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trailers").font(.headline)
                if let playing {
                    TrailerPlayer(youtubeID: playing)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(.rect(cornerRadius: 12))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(release.videoIDs.prefix(8), id: \.self) { id in
                            Button { playing = id } label: {
                                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                                }
                                .frame(width: 200, height: 112)
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay {
                                    Image(systemName: playing == id ? "speaker.wave.2.fill" : "play.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .shadow(radius: 6)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play trailer")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var news: some View {
        let list = stories
        VStack(alignment: .leading, spacing: 12) {
            Text("News").font(.headline)
            if list.isEmpty {
                Text("Nothing about it in your feeds right now.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let env = self.env
                ForEach(list.prefix(12)) { NewsRowCard(story: $0, env: env) }
            }
        }
    }

    /// A wide picture for the top — a screenshot, else IGDB's artwork. Asked
    /// here rather than in the list, which would be a thousand more fields.
    private func loadHero() async {
        guard heroImageID == nil else { return }
        let rows = await IGDBService.raw(
            endpoint: "games",
            query: "where id = \(release.id); fields artworks.image_id, screenshots.image_id; limit 1;")
        guard let row = rows.first else { return }
        let pick = { (key: String) -> String? in
            ((row[key] as? [[String: Any]])?.first?["image_id"]) as? String
        }
        // Screenshots first: IGDB "artwork" is often a logo on white, which
        // is what LEGO Batman's was.
        heroImageID = pick("screenshots") ?? pick("artworks")
    }
}
