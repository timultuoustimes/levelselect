import SwiftUI
import SwiftData

/// The News tab: every gaming site you follow, four ways.
///
/// **Build 39, schema V7.** Designed on the canvas with Tim on 2026-09-17 in
/// two rounds. The first had three competing layouts (a lead mosaic, your
/// games first, topic rails); he asked whether they could be combined, *"a
/// main news feed, your games, topics, and upcoming releases … that you switch
/// to"*. The second folded Your Games into For You to make room for All,
/// because *"I'd be worried without it that maybe stories people might be
/// interested in would get filtered out and go unseen."*
///
/// - **All** — every story, newest first, sized by what it has.
/// - **For You** — your games first, then the rest ranked. Reorders, never hides.
/// - **Topics** — rails, your systems first. Mac lives here: no live Mac
///   gaming site has a feed, so it is gathered from everyone's stories.
/// - **Upcoming** — every notable release, not just your wishlist.
///
/// Saved and Feeds are places you visit rather than streams you scroll, so
/// they are the two toolbar buttons instead of pills.
struct NewsTab: View {
    enum View_: String, CaseIterable, Identifiable {
        case all, forYou, topics, upcoming
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .forYou: "For You"
            case .topics: "Topics"
            case .upcoming: "New & Upcoming"
            }
        }
    }

    private enum Sheet: Identifiable {
        case story(URL)
        case feeds
        case addGame(String)
        var id: String {
            switch self {
            case .story(let url): "story:\(url.absoluteString)"
            case .feeds: "feeds"
            case .addGame(let name): "add:\(name)"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }, sort: \NewsFeed.sortIndex)
    private var feeds: [NewsFeed]
    @Query(filter: #Predicate<NewsItemState> { $0.deletedAt == nil })
    private var states: [NewsItemState]
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil })
    private var consoles: [Console]

    @State private var reader = GameNewsReader.shared
    @AppStorage("news.view") private var viewRaw = View_.forYou.rawValue
    @AppStorage(NewsOpening.key) private var openInReader = true
    @State private var sheet: Sheet?

    private var view: View_ { View_(rawValue: viewRaw) ?? .forYou }

    private var onFeeds: [NewsFeed] { feeds.filter { !$0.muted } }

    private var snapshots: [FeedSnapshot] {
        onFeeds.map { FeedSnapshot(id: $0.id, url: $0.urlString, title: $0.title) }
    }

    /// Stories from feeds that are on — a switched-off feed disappears at
    /// once rather than at the next refresh.
    private var stories: [FeedStory] {
        let on = Set(onFeeds.map(\.id))
        return reader.stories.filter { on.contains($0.feedID) }
    }

    /// Nothing to show yet because nothing has come back yet.
    private var waitingForFirstFetch: Bool {
        view != .upcoming && !onFeeds.isEmpty && stories.isEmpty
            && (reader.refreshing || reader.lastRefresh == nil)
    }

    /// Every feed failed and there is nothing cached to fall back on.
    private var nothingArrived: Bool {
        view != .upcoming && !onFeeds.isEmpty && stories.isEmpty && !reader.refreshing
            && reader.lastRefresh != nil && !reader.problems.isEmpty
    }

    private var savedCount: Int { states.filter { $0.saved && !$0.read }.count }

    private var env: NewsEnv {
        NewsEnv.make(feeds: feeds, states: states, context: context, reader: reader) { url in
            #if os(iOS)
            sheet = .story(url)
            #else
            openURL(url)
            #endif
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if waitingForFirstFetch {
                    ProgressView("Fetching your feeds…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if nothingArrived {
                    ContentUnavailableView {
                        Label("Couldn't reach your feeds", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try Again") { Task { await refresh(true) } }.buttonStyle(.borderedProminent)
                    }
                } else {
                switch view {
                case .all: NewsAllView(stories: stories, env: env, refresh: refresh)
                case .forYou: NewsForYouView(stories: stories, games: games, consoles: consoles,
                                             env: env, refresh: refresh, showAll: { viewRaw = View_.all.rawValue })
                case .topics: NewsTopicsView(stories: stories, consoles: consoles, games: games, env: env, refresh: refresh)
                case .upcoming: NewsUpcomingView(games: games, consoles: consoles,
                                                 addToWishlist: { sheet = .addGame($0) })
                }
                }
            }
            .overlay {
                if onFeeds.isEmpty && view != .upcoming {
                    ContentUnavailableView {
                        Label("No feeds on", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Switch some on, or add a site you read.")
                    } actions: {
                        Button("Feeds") { sheet = .feeds }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .safeAreaBar(edge: .top) { pills }
            .lsBackground()
            .navigationTitle("News")
            .toolbarTitleDisplayMode(.inlineLarge)
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .toolbar {
                if !LSTab.wishlistInLibrary {
                    ToolbarItem { SearchButton() }
                }
                ToolbarItem {
                    NavigationLink(value: NewsRoute.saved) {
                        Label(savedCount > 0 ? "Saved, \(savedCount) unread" : "Saved", systemImage: "bookmark")
                    }
                    .badge(savedCount)
                }
                ToolbarItem {
                    Button { sheet = .feeds } label: {
                        Label("Feeds", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
            // Value-based, like every other push here. `isPresented:` beside
            // the `for:` destinations sent Saved into a redraw loop that
            // pinned the CPU (Tim, 09-18: "I clicked the bookmark and it
            // froze on me").
            .navigationDestination(for: NewsRoute.self) { route in
                switch route {
                case .saved: NewsSavedView()
                }
            }
            .navigationDestination(for: NewsTopic.self) { topic in
                NewsStoryListView(title: topic.title,
                                  stories: stories.filter { topic.matches($0, group: env.feedGroups[$0.feedID]) },
                                  env: env)
            }
            .gamePageDestinations()
            .navigationDestination(for: NewsForYou.GameGroup.self) { group in
                NewsStoryListView(title: group.name, stories: group.stories, env: env)
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .story(let url):
                #if os(iOS)
                SafariView(url: url, reader: openInReader).ignoresSafeArea()
                #else
                EmptyView()
                #endif
            case .feeds:
                NewsFeedsSheet(consoles: consoles).lsSheet([.large])
            case .addGame(let name):
                AddGameSheet(initialSearch: name, defaultStatus: .wishlist).lsSheet()
            }
        }
        .task {
            let repo = Repository(context)
            repo.seedStarterFeedsIfNeeded()
            repo.dedupeFeeds()
        }
        .task(id: snapshots.map(\.id)) {
            reader.keepOnly(Set(onFeeds.map(\.id)))
            await refresh(false)
        }
    }

    private func refresh(_ force: Bool) async {
        await reader.refresh(snapshots, force: force)
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(View_.allCases) { option in
                    let on = option == view
                    Button { viewRaw = option.rawValue } label: {
                        Text(option.label)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(on ? LSTheme.onAccent : .primary)
                            .background(on ? AnyShapeStyle(LSTheme.accentFill) : AnyShapeStyle(.quaternary),
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
}

enum NewsRoute: Hashable { case saved }

/// What every story card needs to know and do, handed down as one value.
struct NewsEnv {
    let feedNames: [UUID: String]
    let feedGroups: [UUID: FeedCatalog.Group]
    let saved: Set<String>
    let read: Set<String>
    let image: (FeedStory) -> URL?
    let open: (FeedStory) -> Void
    let toggleSave: (FeedStory) -> Void

    /// The one way to build it, so a sheet can make its own rather than
    /// being handed the tab's (see `NewsSavedView` for why that matters).
    @MainActor
    static func make(feeds: [NewsFeed], states: [NewsItemState], context: ModelContext,
                     reader: GameNewsReader, show: @escaping (URL) -> Void) -> NewsEnv {
        let saved = Set(states.filter(\.saved).map { "\($0.feedID?.uuidString ?? "")|\($0.guid)" })
        let read = Set(states.filter(\.read).map { "\($0.feedID?.uuidString ?? "")|\($0.guid)" })
        var names: [UUID: String] = [:]
        var groups: [UUID: FeedCatalog.Group] = [:]
        for f in feeds {
            names[f.id] = f.title
            groups[f.id] = FeedCatalog.entry(forFeedURL: f.urlString)?.group
        }
        let repo = Repository(context)
        return NewsEnv(
            feedNames: names, feedGroups: groups, saved: saved, read: read,
            image: { reader.image(for: $0) },
            open: { story in
                repo.markRead(story)
                if let url = story.link { show(url) }
            },
            toggleSave: { story in repo.setSaved(story, !saved.contains(story.id)) })
    }

    func source(_ s: FeedStory) -> String { feedNames[s.feedID] ?? "" }
    func isSaved(_ s: FeedStory) -> Bool { saved.contains(s.id) }
    func isRead(_ s: FeedStory) -> Bool { read.contains(s.id) }
}

// MARK: - All

struct NewsAllView: View {
    let stories: [FeedStory]
    let env: NewsEnv
    let refresh: (Bool) async -> Void

    /// When you last opened All — the "caught up to here" line sits there.
    @AppStorage("news.lastVisitAll") private var lastVisitStored: Double = 0
    /// This visit's line, fixed on arrival so it doesn't jump while you read.
    @State private var marker: Date?
    @State private var expanded: Set<String> = []

    private var blocks: [NewsRiver.Block] {
        NewsRiver.blocks(stories, lastVisit: marker, expanded: expanded)
    }

    private var newCount: Int {
        guard let marker else { return 0 }
        return stories.filter { ($0.published ?? .distantPast) > marker && !env.isRead($0) }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await refresh(true) }
        .onAppear {
            if marker == nil {
                marker = lastVisitStored > 0 ? Date(timeIntervalSince1970: lastVisitStored) : nil
                lastVisitStored = Date.now.timeIntervalSince1970
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: NewsRiver.Block) -> some View {
        switch block {
        case .day(let label):
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
                Spacer()
                if label == "Today", newCount > 0 {
                    Text("\(newCount) new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Mark all read") {
                        marker = .now
                        lastVisitStored = Date.now.timeIntervalSince1970
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
        case .big(let s):
            NewsBigCard(story: s, env: env, dek: true, unread: isNew(s))
        case .pair(let a, let b):
            HStack(alignment: .top, spacing: 12) {
                NewsTileCard(story: a, env: env, imageHeight: 96, unread: isNew(a))
                NewsTileCard(story: b, env: env, imageHeight: 96, unread: isNew(b))
            }
        case .row(let s):
            NewsRowCard(story: s, env: env, unread: isNew(s))
        case .burst(let feedID, let list):
            Button {
                withAnimation { _ = expanded.insert(block.id) }
            } label: {
                HStack {
                    Text("\(env.feedNames[feedID] ?? "This site") posted \(list.count) more")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Show").foregroundStyle(LSTheme.accent)
                }
                .font(.subheadline)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        case .caughtUp:
            HStack(spacing: 10) {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("You're caught up to here").font(.caption).foregroundStyle(.secondary).fixedSize()
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.vertical, 4)
        }
    }

    private func isNew(_ s: FeedStory) -> Bool {
        guard let marker else { return false }
        return (s.published ?? .distantPast) > marker && !env.isRead(s)
    }
}

// MARK: - For You

struct NewsForYouView: View {
    let stories: [FeedStory]
    let games: [Game]
    let consoles: [Console]
    let env: NewsEnv
    let refresh: (Bool) async -> Void
    let showAll: () -> Void

    private var owned: Set<NewsTopic> {
        NewsTopic.owned(platforms: consoles.map(\.platform) + games.filter { $0.status != .wishlist }.flatMap(\.platforms))
    }

    private var page: NewsForYou.Page {
        let matcher = GameNewsMatcher(games: games.map { ($0.id, $0.name, $0.status.rawValue) })
        return NewsForYou.page(stories, matcher: matcher, owned: owned, groups: env.feedGroups)
    }

    /// The next wishlist game out within a fortnight, as a countdown card.
    private var nextRelease: (game: Game, days: Int)? {
        let now = Date.now
        let soon = games.filter { $0.status == .wishlist }
            .compactMap { g -> (Game, Date)? in
                guard let d = g.firstReleaseDate, d > now, d < now.addingTimeInterval(14 * 86_400) else { return nil }
                return (g, d)
            }
            .min { $0.1 < $1.1 }
        guard let soon else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let days = utc.dateComponents([.day], from: utc.startOfDay(for: now), to: utc.startOfDay(for: soon.1)).day ?? 0
        return (soon.0, max(days, 0))
    }

    var body: some View {
        let page = self.page
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !page.yourGames.isEmpty {
                    header("About your games", trailing: "Playing · Wishlist")
                    yourGames(page.yourGames)
                }
                header("Picked for you", trailing: ownedLine)
                mosaic(page.picked)
                Text("For You reorders; it never hides. Everything here is also in ")
                    .foregroundStyle(.secondary)
                + Text("All").foregroundStyle(LSTheme.accent)
                + Text(".").foregroundStyle(.secondary)
            }
            .font(.body)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await refresh(true) }
    }

    private var ownedLine: String {
        NewsTopic.ordered(owned: owned).filter { owned.contains($0) }.prefix(3).map(\.title).joined(separator: " · ")
    }

    private func header(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func yourGames(_ groups: [NewsForYou.GameGroup]) -> some View {
        let all = groups.flatMap { g in g.stories.map { (g, $0) } }
        if let lead = all.first(where: { env.image($0.1) != nil }) ?? all.first {
            NewsBigCard(story: lead.1, env: env, dek: false, badge: lead.0.name)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.name) · \(group.stories.count)")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .foregroundStyle(LSTheme.onAccent)
                                .background(LSTheme.accentFill.opacity(0.9), in: .capsule)
                            Text(group.stories.first?.title ?? "")
                                .font(.footnote)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 170, alignment: .topLeading)
                        .padding(10)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(LSTheme.cardFill, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    /// Two columns, cards of differing heights — the magazine page.
    @ViewBuilder
    private func mosaic(_ picked: [FeedStory]) -> some View {
        if picked.isEmpty {
            Text("Nothing new in the last few days.")
                .foregroundStyle(.secondary)
        } else {
            let heights: [CGFloat] = [118, 150, 92, 132]
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(Array(picked.enumerated()).filter { $0.offset % 2 == 0 }, id: \.element.id) { i, s in
                        NewsTileCard(story: s, env: env, imageHeight: heights[(i / 2) % heights.count])
                    }
                }
                VStack(spacing: 12) {
                    if let next = nextRelease {
                        countdown(next.game, days: next.days)
                    }
                    ForEach(Array(picked.enumerated()).filter { $0.offset % 2 == 1 }, id: \.element.id) { i, s in
                        NewsTileCard(story: s, env: env, imageHeight: heights[(i / 2 + 1) % heights.count])
                    }
                }
            }
        }
    }

    private func countdown(_ game: Game, days: Int) -> some View {
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 4) {
                Text(days == 0 ? "OUT TODAY" : days == 1 ? "OUT TOMORROW" : "ON YOUR WISHLIST")
                    .font(.caption2.weight(.bold))
                    .kerning(0.4)
                if days > 1 {
                    Text("\(days) days").font(.system(size: 30, weight: .semibold))
                }
                Text(game.name).font(.footnote).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(LSTheme.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(LSTheme.accentFill, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(days > 1 ? "\(game.name), out in \(days) days" : "\(game.name), out soon")
    }
}

// MARK: - Topics

struct NewsTopicsView: View {
    let stories: [FeedStory]
    let consoles: [Console]
    let games: [Game]
    let env: NewsEnv
    let refresh: (Bool) async -> Void

    @AppStorage("news.hiddenTopics") private var hiddenRaw = ""

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    private var owned: Set<NewsTopic> {
        NewsTopic.owned(platforms: consoles.map(\.platform) + games.filter { $0.status != .wishlist }.flatMap(\.platforms))
    }

    private var rails: [(NewsTopic, [FeedStory])] {
        NewsTopic.ordered(owned: owned).compactMap { topic in
            guard !hidden.contains(topic.rawValue) else { return nil }
            let list = stories.filter { topic.matches($0, group: env.feedGroups[$0.feedID]) }
            return list.isEmpty ? nil : (topic, list)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(rails, id: \.0) { topic, list in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(topic.title).font(.title3.weight(.semibold))
                            Text("\(list.count)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            NavigationLink("See all", value: topic).font(.subheadline)
                        }
                        .padding(.horizontal)
                        .contextMenu {
                            Button("Hide \(topic.title)", systemImage: "eye.slash") { setHidden(topic, true) }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(list.prefix(10)) { s in
                                    NewsTileCard(story: s, env: env, imageHeight: 100)
                                        .frame(width: 170)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                let hiddenTopics = NewsTopic.allCases.filter { hidden.contains($0.rawValue) }
                if !hiddenTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hidden").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(hiddenTopics) { t in
                                Button("Show \(t.title)") { setHidden(t, false) }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Text("Your systems come first. Mac gathers stories from every feed, since no Mac gaming site publishes one. Press and hold a topic to hide it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await refresh(true) }
    }

    private func setHidden(_ topic: NewsTopic, _ hide: Bool) {
        var set = hidden
        if hide { set.insert(topic.rawValue) } else { set.remove(topic.rawValue) }
        hiddenRaw = set.sorted().joined(separator: ",")
    }
}

/// A plain list of stories — a topic's See All, one game's news.
struct NewsStoryListView: View {
    let title: String
    let stories: [FeedStory]
    let env: NewsEnv

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(stories.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }) { s in
                    NewsRowCard(story: s, env: env, unread: false)
                }
            }
            .padding()
        }
        .lsBackground()
        .navigationTitle(title)
    }
}

// MARK: - Cards

/// Flat color for a story with no picture, steady per site so a text-only
/// feed still reads as itself.
private func standIn(_ feedID: UUID) -> Color {
    let hue = Double(abs(feedID.hashValue % 360)) / 360
    return Color(hue: hue, saturation: 0.35, brightness: 0.28)
}

private struct StoryImage: View {
    let story: FeedStory
    let env: NewsEnv
    let height: CGFloat
    @State private var reader = GameNewsReader.shared

    var body: some View {
        let url = env.image(story)
        // The picture is an OVERLAY on a frame that sets the size. Laid out
        // directly, a `scaledToFill` image claims its own width, and one wide
        // picture pushed For You's two columns off both sides of the screen.
        standIn(story.feedID)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
        .task(id: story.id) {
            if url == nil { await reader.pageImage(for: story) }
        }
        .accessibilityHidden(true)
    }
}

private struct StoryMeta: View {
    let story: FeedStory
    let env: NewsEnv
    var unread = false

    var body: some View {
        HStack(spacing: 4) {
            if unread {
                Circle().fill(LSTheme.accentFill).frame(width: 7, height: 7)
                    .accessibilityLabel("New")
            }
            Text(env.source(story))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LSTheme.accent)
                .lineLimit(1)
            if let d = story.published {
                Text("· \(Self.age(d))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { env.toggleSave(story) } label: {
                Image(systemName: env.isSaved(story) ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(env.isSaved(story) ? LSTheme.accent : .secondary)
                    .frame(width: 28, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .lsTapTargetTall(11)
            .accessibilityLabel(env.isSaved(story) ? "Remove from saved" : "Save for later")
        }
    }

    static func age(_ date: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Shared tap, press and context menu for every card shape.
private struct StoryButton<Content: View>: View {
    let story: FeedStory
    let env: NewsEnv
    @ViewBuilder let label: () -> Content
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { env.open(story) } label: { label() }
            .buttonStyle(PressableCardStyle())
            .contextMenu {
                Button(env.isSaved(story) ? "Remove from Saved" : "Save for Later",
                       systemImage: env.isSaved(story) ? "bookmark.slash" : "bookmark") { env.toggleSave(story) }
                if let link = story.link {
                    ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button("Open in Browser", systemImage: "safari") { openURL(link) }
                }
            }
    }
}

struct NewsBigCard: View {
    let story: FeedStory
    let env: NewsEnv
    var dek = true
    var badge: String? = nil
    var unread = false

    var body: some View {
        StoryButton(story: story, env: env) {
            VStack(alignment: .leading, spacing: 0) {
                StoryImage(story: story, env: env, height: 160)
                    .overlay(alignment: .bottomLeading) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(LSTheme.onAccent)
                                .background(LSTheme.accentFill, in: .capsule)
                                .padding(12)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    StoryMeta(story: story, env: env, unread: unread)
                    Text(story.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    if dek, let summary = story.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(12)
            }
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
        }
    }
}

/// A tile: picture on top when there is one, text only when there isn't.
struct NewsTileCard: View {
    let story: FeedStory
    let env: NewsEnv
    var imageHeight: CGFloat = 100
    var unread = false

    var body: some View {
        StoryButton(story: story, env: env) {
            VStack(alignment: .leading, spacing: 0) {
                if env.image(story) != nil {
                    StoryImage(story: story, env: env, height: imageHeight)
                } else {
                    StoryImage(story: story, env: env, height: 0).hidden().frame(height: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    StoryMeta(story: story, env: env, unread: unread)
                    Text(story.title)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .lineLimit(5)
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 14))
            .clipShape(.rect(cornerRadius: 14))
        }
    }
}

struct NewsRowCard: View {
    let story: FeedStory
    let env: NewsEnv
    var unread = false

    var body: some View {
        StoryButton(story: story, env: env) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    StoryMeta(story: story, env: env, unread: unread)
                    Text(story.title)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }
                if env.image(story) != nil {
                    StoryImage(story: story, env: env, height: 72)
                        .frame(width: 72)
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    // Asks the page for a picture without taking room.
                    StoryImage(story: story, env: env, height: 0).frame(width: 0).hidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .opacity(env.isRead(story) && !unread ? 0.6 : 1)
        }
    }
}
