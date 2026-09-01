import SwiftUI

/// Add Game: IGDB search-first (by name OR numeric IGDB id), tap a result →
/// quick Platform + Status confirm → Add. Manual entry stays as a fallback
/// for games not on IGDB.
struct AddGameSheet: View {
    /// Pre-filled search (e.g. promoting a Deku wishlist item) and an optional
    /// status override (wishlist promotions default to `.wishlist`).
    init(initialSearch: String = "", defaultStatus: GameStatus? = nil) {
        _searchText = State(initialValue: initialSearch)
        self.defaultStatus = defaultStatus
    }

    private let defaultStatus: GameStatus?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastPlatform") private var lastPlatform = ""
    @AppStorage("lastStatusRaw") private var lastStatusRaw = GameStatus.playing.rawValue

    @State private var searchText: String
    @State private var results: [IGDBGame] = []
    @State private var idMatch: IGDBGame?
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var selected: IGDBGame?
    @State private var manualMode = false

    var body: some View {
        NavigationStack {
            Group {
                if manualMode {
                    manualForm
                } else if let selected {
                    ConfirmAddView(
                        game: selected,
                        lastPlatform: lastPlatform,
                        lastStatus: defaultStatus ?? GameStatus(rawValue: lastStatusRaw) ?? .playing,
                        onBack: { self.selected = nil },
                        onAdd: add(igdb:platform:status:ownership:)
                    )
                } else {
                    searchStage
                }
            }
            .navigationTitle(selected == nil ? "Add Game" : "Confirm")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(LSTheme.accent)
        // The whole sheet, not just its rows. Tim: "Can the entire menu be
        // slightly translucent, like a frosted glass?" — the library behind it
        // staying faintly visible is what makes this read as a layer over your
        // games rather than a separate grey screen.
        #if !os(macOS)
        .presentationBackground(.ultraThinMaterial)
        #endif
    }

    // MARK: Search stage

    private var searchStage: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search IGDB — name or ID number", text: $searchText)
                    .textFieldStyle(.plain)
                    #if !os(macOS)
                    .autocorrectionDisabled()
                    #endif
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .background(AddSheetCard(cornerRadius: 12))
            .padding()

            List {
                // Failure/empty states live INSIDE the list, above the manual
                // fallback — as a full-list overlay they visually covered the
                // one path that still works with no network and no IGDB match,
                // which is a dead end at the exact moment a new user's game
                // isn't found.
                if searchFailed {
                    Section {
                        ContentUnavailableView(
                            "Search failed",
                            systemImage: "wifi.exclamationmark",
                            description: Text("Check your connection and try again — or add the game manually below."))
                        .listRowBackground(Color.clear)
                    }
                } else if noResults {
                    Section {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    }
                }
                if let idMatch {
                    Section("ID match") {
                        resultRow(idMatch, badge: "#\(idMatch.id)")
                    }
                }
                if !results.isEmpty {
                    Section(idMatch == nil ? "Results" : "Name results") {
                        ForEach(results) { game in
                            resultRow(game, badge: nil)
                        }
                    }
                }
                Section {
                    Button {
                        manualMode = true
                    } label: {
                        Label("Add manually (not on IGDB)", systemImage: "square.and.pencil")
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            // The search results list painted its own opaque grey over the
            // frosted sheet, which is why only the strip around the search
            // field looked translucent and everything below it did not.
            .scrollContentBackground(.hidden)
            .listRowBackground(AddSheetCard())
        }
        .task(id: searchText) {
            // Debounce; .task(id:) cancels the previous search automatically.
            try? await Task.sleep(for: .milliseconds(350))
            await runSearch()
        }
    }

    private var noResults: Bool {
        !isSearching && results.isEmpty && idMatch == nil
            && searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    private func resultRow(_ game: IGDBGame, badge: String?) -> some View {
        Button {
            selected = game
        } label: {
            HStack(spacing: 12) {
                CoverThumb(urlString: game.coverURLString)
                    .frame(width: 54, height: 72)
                    .coverGloss(cornerRadius: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let year = game.releaseYear {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                    // The systems it is on, drawn rather than spelled out.
                    // "PC (Microsoft Windows) +3" is the longest way to say
                    // something a row of icons says at a glance.
                    HStack(spacing: 4) {
                        ForEach(PlatformPreference.sorted(game.platforms).prefix(4), id: \.self) { p in
                            PlatformIconView(platform: p, size: 19)
                        }
                        if game.platforms.count > 4 {
                            Text("+\(game.platforms.count - 4)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if let type = game.typeLabel {
                    Text(type)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.gray.opacity(0.3), in: .capsule)
                        .foregroundStyle(.secondary)
                }
                if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(LSTheme.accent.opacity(0.25), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func runSearch() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        searchFailed = false
        guard text.count >= 2 else {
            results = []; idMatch = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            if let numericID = Int(text) {
                // Numeric: id lookup AND name search (some games have numeric names).
                async let byID = IGDBService.lookup(id: numericID)
                async let byName = (try? IGDBService.search(name: text)) ?? []
                idMatch = try await byID
                let named = await byName
                results = named.filter { $0.id != idMatch?.id }
            } else {
                idMatch = nil
                results = try await IGDBService.search(name: text)
            }
        } catch is CancellationError {
            // superseded by newer keystroke — ignore
        } catch {
            if !Task.isCancelled { searchFailed = true }
        }
    }

    // MARK: Manual fallback

    @State private var manualName = ""
    @State private var manualPlatform = ""
    @State private var manualStatus: GameStatus = .playing

    private var manualForm: some View {
        Form {
            Section {
                TextField("Name", text: $manualName)
                TextField("Platform", text: $manualPlatform)
                Picker("Status", selection: $manualStatus) {
                    ForEach(GameStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Button("Add") {
                    let trimmed = manualName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let repo = Repository(context)
                    let game = repo.addGame(name: trimmed, status: manualStatus)
                    let p = manualPlatform.trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty { repo.edit(game) { $0.platforms = [p] }; lastPlatform = p }
                    lastStatusRaw = manualStatus.rawValue
                    dismiss()
                }
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back to search") { manualMode = false }
            }
        }
        .onAppear {
            manualName = searchText
            manualPlatform = lastPlatform
            manualStatus = GameStatus(rawValue: lastStatusRaw) ?? .playing
        }
    }

    // MARK: Add

    private func add(igdb: IGDBGame, platform: String?, status: GameStatus, ownership: [String]) {
        let repo = Repository(context)
        let game = repo.addGame(from: igdb, platform: platform, status: status)
        // Built-ins were only attached at launch, so a game added now didn't
        // get its hand-built tracker (Hades, Hollow Knight, Dead Cells, …)
        // until the next cold start. Attach immediately instead.
        BuiltinTrackers.installMissing(context: context)
        repo.edit(game) { $0.ownership = ownership }
        if let platform, !platform.isEmpty { lastPlatform = platform }
        // Don't let a wishlist promotion hijack the everyday default status.
        if defaultStatus == nil { lastStatusRaw = status.rawValue }
        dismiss()
    }
}

/// Stage 2: cover + metadata preview, pick Platform + Status, Add.
private struct ConfirmAddView: View {
    let game: IGDBGame
    let lastPlatform: String
    let lastStatus: GameStatus
    var onBack: () -> Void
    var onAdd: (IGDBGame, String?, GameStatus, [String]) -> Void

    @State private var platform: String = ""
    @State private var customPlatform: String = ""
    private let customOption = "Other…"

    @State private var status: GameStatus = .playing
    @State private var ownership: [String] = []
    @State private var preview = GamePreview()
    @State private var showingAbout = false
    @State private var zoomed: ZoomTarget?
    @State private var browsing: DekuLinkTarget?
    @State private var trailer: TrailerTarget?

    /// Picker options in preference order (Switch 2 → Switch → PC → …).
    private var orderedPlatforms: [String] {
        PlatformPreference.sorted(game.platforms)
    }

    /// IGDB's platform lists are community data and sometimes incomplete
    /// (e.g. bundles missing their Switch release). Offer the preferred
    /// Nintendo platforms even when IGDB omits them, plus free entry.
    private var extraPlatforms: [String] {
        ["Nintendo Switch 2", "Nintendo Switch"].filter { extra in
            !game.platforms.contains { $0.caseInsensitiveCompare(extra) == .orderedSame }
        }
    }

    /// The platform currently chosen, as the date resolver sees it.
    private var chosen: String? {
        let name = platform == customOption
            ? customPlatform.trimmingCharacters(in: .whitespaces) : platform
        return name.isEmpty ? nil : name
    }

    /// What this platform means for when you get it.
    ///
    /// The picker was already deciding the stored date and never said so, so
    /// choosing PC over Switch 2 silently changed a game's release by months
    /// with nothing on screen. It is the reason the picker is here, so it says
    /// what it is doing.
    private var releaseLine: (text: String, isCountdown: Bool)? {
        guard let date = game.storableReleaseDate(on: chosen),
              !MetadataRefresh.isMissing(date) else { return nil }
        if let soon = ReleaseCountdown.countdown(to: date) {
            return ("Releases \(ReleaseCountdown.dateLabel(date)) · \(soon)", true)
        }
        if ReleaseCountdown.isYearOnly(date) {
            return ("No date announced for this platform — \(ReleaseCountdown.dateLabel(date))", false)
        }
        return ("Released \(ReleaseCountdown.dateLabel(date))", false)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    // Big enough to judge, and tappable, because deciding
                    // "is this the right game" is what this screen is for.
                    Button {
                        zoomed = game.coverImageID
                            .flatMap { URL(string: "https://images.igdb.com/igdb/image/upload/t_720p/\($0).jpg") }
                            .map(ZoomTarget.init)
                    } label: {
                        CoverThumb(urlString: game.coverURLString)
                            .frame(width: 110, height: 147)
                            .coverGloss(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(game.coverImageID == nil)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.name).font(.headline)
                        HStack(spacing: 4) {
                            if let year = game.releaseYear { Text(String(year)) }
                            if let franchise = game.franchise { Text("· \(franchise)") }
                            if let type = game.typeLabel { Text("· \(type)") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text("IGDB #\(String(game.id))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Section {
                Picker("Platform", selection: $platform) {
                    ForEach(orderedPlatforms, id: \.self) { Text($0).tag($0) }
                    if !extraPlatforms.isEmpty {
                        Divider()
                        ForEach(extraPlatforms, id: \.self) { Text($0).tag($0) }
                    }
                    Divider()
                    Text(customOption).tag(customOption)
                }
                if platform == customOption {
                    TextField("Platform name", text: $customPlatform)
                }
                Picker("Status", selection: $status) {
                    ForEach(GameStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Owned").font(.caption).foregroundStyle(.secondary)
                    OwnershipControl(ownership: $ownership)
                }
                if let line = releaseLine {
                    Label(line.text, systemImage: line.isCountdown ? "calendar.badge.clock" : "calendar")
                        .font(.footnote)
                        .foregroundStyle(line.isCountdown ? LSTheme.accent : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                if !extraPlatforms.isEmpty {
                    Text("Platform list from IGDB — sometimes incomplete; pick or type the real one.")
                }
            }

            if let summary = game.summary, !MetadataRefresh.isMissing(summary: summary) {
                Section("About") {
                    Text(summary)
                        .font(.footnote)
                        .lineLimit(showingAbout ? nil : 4)
                    Button(showingAbout ? "Less" : "More") { showingAbout.toggle() }
                        .font(.footnote)
                }
            }

            if !preview.screenshotIDs.isEmpty {
                Section("Screenshots") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(preview.screenshotIDs, id: \.self) { id in
                                Button {
                                    zoomed = URL(string:
                                        "https://images.igdb.com/igdb/image/upload/t_1080p/\(id).jpg")
                                        .map(ZoomTarget.init)
                                } label: {
                                    AsyncImage(url: URL(string:
                                        "https://images.igdb.com/igdb/image/upload/t_screenshot_big/\(id).jpg")) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                                    }
                                    .frame(width: 248, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.white.opacity(0.08), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                }
            }

            Section {
                // Opened in the app's own browser, not handed to Safari.
                // Deciding whether this is the right game is the job of this
                // screen, and being thrown out of it to check a price or a
                // release date is how you lose the search you just did.
                if let video = game.videoIDs.first {
                    Button {
                        trailer = TrailerTarget(youtubeID: video, title: game.name)
                    } label: {
                        Label("Watch the trailer", systemImage: "play.rectangle.fill")
                    }
                }
                Button { browsing = DekuLinkTarget(url: DekuLinks.search(for: game.name)) } label: {
                    Label("Look it up on Deku Deals", systemImage: "tag.fill")
                }
                if let slug = game.slug,
                   let url = URL(string: "https://www.igdb.com/games/\(slug)") {
                    Button { browsing = DekuLinkTarget(url: url) } label: {
                        Label("Open the IGDB page", systemImage: "arrow.up.right.square")
                    }
                }
            }

            if !game.developers.isEmpty || !game.publishers.isEmpty || !game.genres.isEmpty {
                Section("Game info") {
                    if !game.developers.isEmpty {
                        LabeledContent("Developer", value: game.developers.joined(separator: ", "))
                    }
                    if !game.publishers.isEmpty {
                        LabeledContent("Publisher", value: game.publishers.joined(separator: ", "))
                    }
                    if !game.genres.isEmpty {
                        LabeledContent("Genre", value: game.genres.joined(separator: ", "))
                    }
                }
                .font(.footnote)
            }

            Section {
                // Follows the status, but only for Wishlist. Every other
                // status describes a game you have, so "Library" is the right
                // word for them; Wishlist is the one that means you don't own
                // it yet, and being told you're adding it to your library is
                // the sentence that reads wrong at exactly that moment.
                Button(status == .wishlist ? "Add to Wishlist" : "Add to Library") {
                    let chosen = platform == customOption
                        ? customPlatform.trimmingCharacters(in: .whitespaces)
                        : platform
                    onAdd(game, chosen.isEmpty ? nil : chosen, status, ownership)
                }
                .font(.headline)
                Button("Back to search", action: onBack)
            }
        }
        // The app's own ground, with the rows as glass on top of it. A system
        // grouped Form reads as Settings, and this is the screen where you
        // look at a game — Tim: "It's also a boring default grey, like the
        // settings menu... Can it be a slight glass?"
        // No `lsBackground()` here on purpose. An opaque ground painted
        // inside the sheet sits ON TOP of `presentationBackground`, so the
        // frosting had nothing to frost — the sheet was translucent in name
        // and grey on screen. The material is the background now.
        .scrollContentBackground(.hidden)
        .listRowBackground(AddSheetCard())
                .sheet(item: $zoomed) { RemoteImageViewer(url: $0.url) }
        // The same modifier the game page uses, so a link opens the same way
        // from both — Tim: "Igdb and Deku both open a little differently than
        // they open straight from the game's page." That one is Safari's own
        // compact bar; mine was a full navigation bar around a web view.
        .dekuBrowser(target: $browsing)
        .sheet(item: $trailer) { TrailerSheet(youtubeID: $0.youtubeID, title: $0.title) }
        .task { preview = await GamePreviewService.load(igdbID: game.id) }
        .onAppear {
            status = lastStatus
            // Default: highest-preference platform (Switch 2 → Switch → PC)
            // when the game supports one; otherwise the last platform picked;
            // otherwise IGDB's first; otherwise free entry.
            if let top = orderedPlatforms.first, PlatformPreference.rank(top) < 100 {
                platform = top
            } else if game.platforms.contains(lastPlatform) {
                platform = lastPlatform
            } else if let first = orderedPlatforms.first {
                platform = first
            } else {
                platform = customOption
            }
        }
    }
}
