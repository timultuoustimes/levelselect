import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Saved

/// Stories kept to read later. Synced, since `NewsItemState` is.
struct NewsSavedView: View {
    // **Takes no inputs, on purpose.** It was handed the tab's feeds and its
    // `NewsEnv` — closures rebuilt on every redraw of the tab — so every
    // redraw read as a new destination. Updating the pushed screen redrew the
    // tab, which made another new destination: a loop that pinned the CPU and
    // froze the app the moment Saved opened (Tim, 09-18, on device). It
    // queries what it shows instead.
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }) private var feeds: [NewsFeed]

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<NewsItemState> { $0.deletedAt == nil && $0.saved },
           sort: \NewsItemState.updatedAt, order: .reverse)
    private var saved: [NewsItemState]
    @State private var showUnreadOnly = true
    @State private var reader = GameNewsReader.shared
    #if os(iOS)
    @State private var browsing: DekuLinkTarget?
    #endif

    private var shown: [NewsItemState] { showUnreadOnly ? saved.filter { !$0.read } : saved }

    var body: some View {
        List {
            Picker("Show", selection: $showUnreadOnly) {
                Text("Unread · \(saved.filter { !$0.read }.count)").tag(true)
                Text("All · \(saved.count)").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if shown.isEmpty {
                Text(saved.isEmpty ? "Tap the bookmark on any story to keep it here."
                                   : "You've read everything you saved.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(shown) { item in
                Button { open(item) } label: { row(item) }
                    .buttonStyle(.plain)
                    .listRowBackground(LSTheme.cardFill)
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                            Repository(context).unsave(item)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button(item.read ? "Unread" : "Read", systemImage: item.read ? "circle" : "checkmark.circle") {
                            Repository(context).setRead(item, !item.read)
                        }
                        .tint(LSTheme.accent)
                    }
                    .contextMenu {
                        if let link = item.linkString.flatMap(URL.init(string:)) {
                            ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                        Button("Remove from Saved", systemImage: "bookmark.slash") { Repository(context).unsave(item) }
                    }
            }
            Text("Swipe left to remove, right to mark read. Saved stories reach your other devices; read ones leave Unread but stay here until removed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .lsBackground()
        .navigationTitle("Saved")
        #if os(iOS)
        .newsBrowser(target: $browsing)
        #endif
    }

    private func row(_ item: NewsItemState) -> some View {
        let story = reader.stories.first { $0.feedID == item.feedID && $0.guid == item.guid }
        let image = story.flatMap { reader.image(for: $0) }
        return HStack(spacing: 12) {
            Group {
                if let image {
                    AsyncImage(url: image) { phase in
                        if case .success(let i) = phase { i.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                    }
                } else {
                    Color.secondary.opacity(0.15).overlay(Image(systemName: "newspaper").foregroundStyle(.secondary))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(feeds.first { $0.id == item.feedID }?.title ?? "")
                    .font(.caption2.weight(.semibold)).foregroundStyle(LSTheme.accent)
                Text(item.title ?? "Untitled").font(.subheadline).lineLimit(3)
                Text(savedLine(item)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .opacity(item.read ? 0.55 : 1)
        .contentShape(.rect)
    }

    private func savedLine(_ item: NewsItemState) -> String {
        let when = item.updatedAt.formatted(.relative(presentation: .named))
        return item.read ? "Read · saved \(when)" : "Saved \(when)"
    }

    private func open(_ item: NewsItemState) {
        Repository(context).setRead(item, true)
        guard let url = item.linkString.flatMap(URL.init(string:)) else { return }
        #if os(iOS)
        browsing = DekuLinkTarget(url: url)
        #else
        openURL(url)
        #endif
    }
}

// MARK: - Feeds

/// Your feeds: switch them on and off, add one, browse the catalog, or bring
/// your own list in from another reader.
struct NewsFeedsSheet: View {
    let consoles: [Console]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }, sort: \NewsFeed.sortIndex)
    private var feeds: [NewsFeed]
    @State private var reader = GameNewsReader.shared
    @State private var importingOPML = false
    @AppStorage(NewsOpening.key) private var openInReader = true
    @State private var opmlEntries: [OPMLParser.Entry]?
    @State private var opmlError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { NewsAddFeedView() } label: {
                        Label("Add a Feed", systemImage: "plus.circle.fill")
                    }
                    NavigationLink { NewsCatalogView(consoles: consoles) } label: {
                        Label("Browse Feeds", systemImage: "square.grid.2x2")
                    }
                    Button { importingOPML = true } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("OPML is the list every reader exports — Inoreader, Feedly, NetNewsWire.")
                }

                #if os(iOS)
                Section {
                    Picker("Open stories in", selection: $openInReader) {
                        Text("Reader").tag(true)
                        Text("Website").tag(false)
                    }
                } footer: {
                    Text("Reader shows the story without the site around it; tap the page menu in the address bar for the full website. Ad blockers you've turned on for Safari work here too — Settings › Apps › Safari › Extensions.")
                }
                #endif

                Section("Following · \(feeds.filter { !$0.muted }.count) on") {
                    ForEach(feeds) { feed in
                        FeedToggleRow(feed: feed, detail: detail(feed))
                    }
                    .onDelete { offsets in
                        let repo = Repository(context)
                        for i in offsets { repo.unfollow(feeds[i]) }
                    }
                }
            }
            .navigationTitle("Feeds")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $importingOPML,
                          allowedContentTypes: [UTType(filenameExtension: "opml") ?? .xml, .xml, .data]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { opmlError = "Couldn't read that file."; return }
                    let entries = OPMLParser.parse(data)
                    if entries.isEmpty { opmlError = "No feeds in that file." } else { opmlEntries = entries }
                case .failure: break
                }
            }
            .navigationDestination(isPresented: Binding(get: { opmlEntries != nil },
                                                        set: { if !$0 { opmlEntries = nil } })) {
                if let opmlEntries { NewsOPMLImportView(entries: opmlEntries) }
            }
            .alert("Import OPML", isPresented: Binding(get: { opmlError != nil }, set: { if !$0 { opmlError = nil } })) {
                Button("OK") {}
            } message: { Text(opmlError ?? "") }
        }
    }

    private func detail(_ feed: NewsFeed) -> String {
        if feed.muted { return "Off" }
        if let problem = reader.problems[feed.id] { return problem }
        let today = reader.stories.filter {
            $0.feedID == feed.id && Calendar.current.isDateInToday($0.published ?? .distantPast)
        }.count
        let topic = FeedCatalog.entry(forFeedURL: feed.urlString)?.group.rawValue ?? feed.folder ?? "Yours"
        return "\(topic) · \(today) today"
    }
}

private struct FeedToggleRow: View {
    let feed: NewsFeed
    let detail: String
    @Environment(\.modelContext) private var context

    var body: some View {
        Toggle(isOn: Binding(get: { !feed.muted },
                             set: { Repository(context).setFeed(feed, on: $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(LSTheme.accent)
    }
}

/// Everything in `FeedCatalog`, your systems' groups first.
struct NewsCatalogView: View {
    let consoles: [Console]
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<NewsFeed> { $0.deletedAt == nil }) private var feeds: [NewsFeed]

    private var groups: [FeedCatalog.Group] {
        let owned = NewsTopic.owned(platforms: consoles.map(\.platform))
        let mine = FeedCatalog.Group.allCases.filter { $0.topic.map(owned.contains) ?? false }
        return [.everything] + mine + FeedCatalog.Group.allCases.filter { $0 != .everything && !mine.contains($0) }
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.rawValue) {
                    ForEach(FeedCatalog.all.filter { $0.group == group }) { entry in
                        Toggle(isOn: binding(entry)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                Text(entry.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(LSTheme.accent)
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Every feed here was checked live in September 2026. There's no Mac section because no Mac gaming site publishes a live feed; the Mac topic gathers Mac stories from all of these instead.")
            }
        }
        .navigationTitle("Browse Feeds")
    }

    private func binding(_ entry: FeedCatalog.Entry) -> Binding<Bool> {
        let key = FeedDiscovery.key(entry.feedURL)
        return Binding(
            get: { feeds.contains { FeedDiscovery.key($0.urlString) == key && !$0.muted } },
            set: { on in
                let repo = Repository(context)
                if on {
                    repo.follow(url: entry.feedURL, title: entry.name, siteURL: entry.siteURL)
                } else if let feed = feeds.first(where: { FeedDiscovery.key($0.urlString) == key }) {
                    repo.setFeed(feed, on: false)
                }
            })
    }
}

/// Paste a site or a feed; the reader finds the feed.
struct NewsAddFeedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var looking = false
    @State private var found: GameNewsReader.Found?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                TextField("nintendolife.com", text: $typed)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await look() } }
                Button { Task { await look() } } label: {
                    if looking { ProgressView() } else { Text("Find Feed") }
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || looking)
            } footer: {
                Text("A site's address is enough — most sites say where their feed is.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(.secondary) }
            }
            if let found {
                Section("Found") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(found.title).font(.headline)
                        Text("\(found.storyCount) recent stories").font(.caption).foregroundStyle(.secondary)
                        Text(found.feedURL).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Button("Follow") {
                        Repository(context).follow(url: found.feedURL, title: found.title, siteURL: found.siteURL)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Add a Feed")
    }

    private func look() async {
        looking = true
        problem = nil
        found = nil
        defer { looking = false }
        do { found = try await GameNewsReader.discover(typed) }
        catch { problem = GameNewsReader.readable(error) }
    }
}

/// Choose which folders of an exported list to bring in.
///
/// Folders whose name says games are ticked to start with; everything else
/// isn't. Tim's own export has Gaming beside Nature & Gardening and Privacy &
/// Security, and a game news tab full of native plant nurseries would be an
/// import that did exactly what it was told and nothing anyone wanted.
struct NewsOPMLImportView: View {
    let entries: [OPMLParser.Entry]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var started = false

    private var folders: [String] {
        var seen: [String] = []
        for e in entries where e.isFetchable {
            let f = e.folder ?? "Not in a folder"
            if !seen.contains(f) { seen.append(f) }
        }
        return seen
    }

    private var skipped: Int { entries.filter { !$0.isFetchable }.count }

    private func feeds(in folder: String) -> [OPMLParser.Entry] {
        entries.filter { $0.isFetchable && ($0.folder ?? "Not in a folder") == folder }
    }

    var body: some View {
        List {
            Section {
                ForEach(folders, id: \.self) { folder in
                    Toggle(isOn: Binding(get: { chosen.contains(folder) },
                                         set: { if $0 { chosen.insert(folder) } else { chosen.remove(folder) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder)
                            Text(feeds(in: folder).prefix(3).map(\.title).joined(separator: ", ")
                                 + (feeds(in: folder).count > 3 ? "…" : ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .badge(feeds(in: folder).count)
                    .tint(LSTheme.accent)
                }
            } header: {
                Text("Folders")
            } footer: {
                if skipped > 0 {
                    Text("\(skipped) \(skipped == 1 ? "entry is" : "entries are") the other reader's own (newsletters, bundles) and can't be fetched from here.")
                }
            }
            Section {
                Button("Import \(chosen.reduce(0) { $0 + feeds(in: $1).count }) Feeds") {
                    let repo = Repository(context)
                    for folder in chosen {
                        for e in feeds(in: folder) {
                            repo.follow(url: e.feedURL, title: e.title, siteURL: e.siteURL,
                                        folder: folder == "Not in a folder" ? nil : folder)
                        }
                    }
                    dismiss()
                }
                .disabled(chosen.isEmpty)
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Import OPML")
        .onAppear {
            guard !started else { return }
            started = true
            chosen = Set(folders.filter { NewsMatch.fold($0).contains("gam") })
        }
    }
}
