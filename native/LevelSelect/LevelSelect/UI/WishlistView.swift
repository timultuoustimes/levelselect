import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Wishlist tab: the games you want, and the Deku Deals list beside them.
///
/// Two lists, deliberately not merged. Yours is IGDB-backed and lives in your
/// library — a real Game with `.wishlist` status, so covers, platforms and
/// everything else work the way they do anywhere else, and buying it is a
/// status change rather than a re-entry. Deku's is a price-watching list that
/// belongs to Deku, kept in its own vocabulary and refreshed from the public
/// share link. Promoting a Deku row into your wishlist is a manual "Add to
/// Library" for now; automatic matching can come later, when a wrong match
/// costs less than it would today.
///
/// On a wide screen both are visible at once: yours fills, Deku sits in a
/// sidebar you can flip between its list and its site. On a phone they share
/// the tab through a segmented control, because a 380pt sidebar on a 393pt
/// screen is not a sidebar.
struct WishlistTab: View {
    /// ONE presentation slot. Two `.sheet` modifiers on the same view is the
    /// bug this project has hit twice — whichever is applied second swallows
    /// the first, silently, and only on device.
    private enum Sheet: Identifiable {
        case browser(URL)
        case addGame(String)

        var id: String {
            switch self {
            case .browser(let url): "browser:\(url.absoluteString)"
            case .addGame(let name): "add:\(name)"
            }
        }
    }

    private enum Pane: String, CaseIterable, Identifiable {
        case yours, deku
        var id: String { rawValue }
        var label: String {
            switch self {
            case .yours: "Yours"
            case .deku: "Deku Deals"
            }
        }
    }

    enum WishlistSort: String, CaseIterable, Identifiable {
        case dateNewest, dateOldest, nameAZ
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dateNewest: "Recently added"
            case .dateOldest: "Oldest first"
            case .nameAZ: "Name (A–Z)"
            }
        }
        var systemImage: String {
            switch self {
            case .dateNewest: "clock.arrow.circlepath"
            case .dateOldest: "clock"
            case .nameAZ: "textformat"
            }
        }
    }

    // Status is filtered in Swift rather than in the predicate: it is stored as
    // a raw string and the library is small enough that the difference is not
    // measurable, while a predicate over an enum is a compile-time gamble.
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var library: [Game]

    @State private var store = DekuWishlistStore()
    @State private var searchText = ""
    @State private var sort: WishlistSort = .dateNewest
    @State private var pane: Pane = .yours
    @State private var sheet: Sheet?
    @State private var paneURL: URL = DekuLinks.home
    @State private var sidebarShowsSite = false
    @State private var urlInput = ""
    /// Driven by ⌘F from the menu bar. See LevelSelectCommands — Wishlist has
    /// its own search, so ⌘F focuses THIS one rather than sending you away.
    @FocusState private var searchFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Scales with text size for the same reason the other browsing grids do.
    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat = 105

    private var isSplit: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Group {
                if isSplit {
                    HStack(spacing: 0) {
                        yours
                        Divider()
                        dekuSidebar
                            .frame(width: 380)
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("Wishlist", selection: $pane) {
                            ForEach(Pane.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        if pane == .yours { yours } else { dekuPane }
                    }
                }
            }
            .lsBackground()
            .navigationTitle("Wishlist")
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .searchable(text: $searchText, prompt: "Search wishlist")
            .searchFocused($searchFocused)
            .onChange(of: AppNavigator.shared.searchRequest) { _, _ in searchFocused = true }
            // Glass, like Home — see LibraryView.
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(WishlistSort.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .addGame("")
                    } label: {
                        Label("Add to Wishlist", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openDeku(DekuLinks.home)
                    } label: {
                        Label("Browse Deku Deals", systemImage: "globe")
                    }
                }
            }
        }
        .sheet(item: $sheet, onDismiss: { Task { await store.refresh() } }) { which in
            switch which {
            case .browser(let url):
                // Unreachable on macOS — `openDeku` hands the URL to the real
                // browser there rather than presenting one.
                #if os(iOS)
                SafariView(url: url)
                    .ignoresSafeArea()
                #else
                EmptyView()
                #endif
            case .addGame(let name):
                AddGameSheet(initialSearch: name, defaultStatus: .wishlist)
            }
        }
        .task {
            if store.isConfigured { await store.refresh() }
        }
    }

    // MARK: Yours

    private var mine: [Game] {
        let base = library.filter { $0.status == .wishlist }
        let matched = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        switch sort {
        case .dateNewest: return matched.sorted { $0.addedAt > $1.addedAt }
        case .dateOldest: return matched.sorted { $0.addedAt < $1.addedAt }
        case .nameAZ:
            return matched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var yours: some View {
        ScrollView {
            if mine.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "Nothing on your wishlist" : "No matches",
                          systemImage: "bag")
                } description: {
                    Text(searchText.isEmpty
                         ? "Games you want but don't own yet. They live in your library with everything else — buying one is a status change, not a re-entry."
                         : "Nothing on your wishlist matches “\(searchText)”.")
                } actions: {
                    if searchText.isEmpty {
                        Button("Add a Game") { sheet = .addGame("") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(mine.count) \(mine.count == 1 ? "game" : "games")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 12)],
                              spacing: 16) {
                        ForEach(mine) { game in
                            NavigationLink(value: game) {
                                LibraryGridCell(game: game, size: .medium)
                            }
                            .buttonStyle(PressableCardStyle())
                            .gameContextMenu(game)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Deku

    private func openDeku(_ url: URL) {
        if isSplit {
            paneURL = url
            sidebarShowsSite = true
            return
        }
        #if os(iOS)
        sheet = .browser(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    /// The sidebar flips between Deku's list and Deku's site rather than
    /// showing both: the list is for finding something, the site is for the
    /// price history that is the reason to keep the list at all.
    private var dekuSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Deku Deals")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if store.isConfigured {
                    Button {
                        sidebarShowsSite.toggle()
                    } label: {
                        Label(sidebarShowsSite ? "Show list" : "Open site",
                              systemImage: sidebarShowsSite ? "list.bullet" : "globe")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            dekuPane
        }
    }

    private var dekuPane: some View {
        Group {
            if !store.isConfigured {
                setupPrompt
            } else if isSplit && sidebarShowsSite {
                DekuBrowserPane(url: $paneURL) {
                    Task { await store.refresh() }
                }
            } else {
                list
            }
        }
    }

    private var visible: [DekuWishlistItem] {
        let base = searchText.isEmpty
            ? store.items
            : store.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        switch sort {
        case .dateNewest:
            return base.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateOldest:
            return base.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .nameAZ:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var list: some View {
        List {
            if let updated = store.lastUpdated {
                Section {
                    EmptyView()
                } footer: {
                    Text("\(store.items.count) games · synced \(updated, format: .relative(presentation: .named))")
                }
            }
            ForEach(visible) { item in
                Button {
                    if let url = item.url { openDeku(url) }
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button {
                        sheet = .addGame(item.name)
                    } label: {
                        // This row is already on a wishlist — the user's, on
                        // Deku Deals. The action is bringing it into
                        // LevelSelect, so that's what it says.
                        Label("Add to LevelSelect", systemImage: "plus.square.on.square")
                    }
                    Button {
                        if let url = item.url { openDeku(url) }
                    } label: {
                        Label("View on Deku Deals", systemImage: "globe")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refresh() }
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ProgressView("Syncing wishlist…")
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("Sync failed", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
            } else if visible.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(_ item: DekuWishlistItem) -> some View {
        HStack(spacing: 10) {
            // A shopping bag reads as "want to buy" rather than "favorited".
            Image(systemName: "bag.fill")
                .font(.caption)
                .foregroundStyle(LSTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let added = item.addedAt {
                        Text("Added \(added, format: .dateTime.month().day().year())")
                    }
                    if let format = item.desiredFormat {
                        Text("· \(format)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    // MARK: Setup

    private var setupPrompt: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 44))
                    .foregroundStyle(LSTheme.accent)
                Text("Connect your Deku Deals wishlist")
                    .font(.title3.bold())
                Text("In Deku Deals: Settings → Sharing → enable “Allow my wishlist to be publicly viewed”, then paste the wishlist link here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("dekudeals.com/wishlist/…", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Connect") {
                    store.configuredURL = urlInput
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(28)
            // Two frames, and both are load-bearing. The 440 keeps the prompt
            // readable instead of stretching one sentence across a 13" iPad.
            // The infinity makes the ROW fill the width so the scroll view
            // does too — without it the whole tab measured 440pt wide, and
            // `lsBackground` paints the view's own frame, so an iPad showed a
            // narrow strip of app floating in bare black with the navigation
            // title stranded outside it.
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
