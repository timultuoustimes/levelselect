import SwiftUI
import SwiftData

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var browserTarget: DekuLinkTarget?

    @State private var pagePlaying: GameVideo?
    @State private var showingCover = false
    @State private var didAutoRefresh = false

    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil }, sort: \GameCollection.name)
    private var collections: [GameCollection]
    @State private var newCollection = false
    @State private var newCollectionName = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Wide-screen sliding stage: 1 = game page, 2 = +tracker, 3 = tracker+videos.
    @State private var stage = 1

    // Playthrough management
    @State private var namingNewPlaythrough = false
    @State private var renamingPlaythrough = false
    @State private var playthroughName = ""
    @State private var confirmingPlaythroughDelete = false

    private var repo: Repository { Repository(context) }

    var body: some View {
        GeometryReader { geo in
            let stageMode = horizontalSizeClass == .regular
                && geo.size.width > geo.size.height
                && game.resolvedTrackerDisplay == .compact
            Group {
                if stageMode {
                    stageLayout(width: geo.size.width)
                } else {
                    VStack(spacing: 0) {
                        if let video = pagePlaying {
                            VideoPlayerDock(video: video) { pagePlaying = nil }
                        }
                        standardScroll(stageMode: false)
                    }
                }
            }
            .onChange(of: pagePlaying != nil) { _, hasVideo in
                if stageMode, hasVideo { stage = 3 }
            }
        }
        .background { ambientBackdrop }
        .overlay {
            if showingCover {
                CoverShowcase(urlString: game.coverURLString, isPresented: $showingCover)
            }
        }
        .task {
            // Heal legacy data on open: the old web export saved empty summaries
            // and capped others at 200 chars. Pull fresh metadata once.
            guard !didAutoRefresh, game.igdbID != nil else { return }
            let summary = game.summary ?? ""
            if summary.isEmpty || summary.count == 200 {
                didAutoRefresh = true
                await repo.refreshFromIGDB(game)
            }
        }
        .dekuBrowser(target: $browserTarget)
        .alert("New Collection", isPresented: $newCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let collection = repo.createCollection(name: name)
                repo.setMembership(collection, game: game, member: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds “\(game.name)” to a new collection.")
        }
        .navigationTitle(game.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        game.pinned.toggle()
                    } label: {
                        Label(game.pinned ? "Unpin" : "Pin", systemImage: game.pinned ? "pin.slash" : "pin")
                    }
                    Menu("Status") {
                        ForEach(GameStatus.allCases, id: \.self) { s in
                            Button {
                                game.status = s
                            } label: {
                                Label(s.label, systemImage: game.status == s ? "checkmark" : s.systemImage)
                            }
                        }
                    }
                    Menu {
                        ForEach(collections) { collection in
                            Button {
                                repo.setMembership(collection, game: game, member: !collection.contains(game))
                            } label: {
                                Label(collection.name,
                                      systemImage: collection.contains(game) ? "checkmark" : "square.stack")
                            }
                        }
                        Divider()
                        Button {
                            newCollectionName = ""; newCollection = true
                        } label: { Label("New Collection…", systemImage: "plus") }
                    } label: {
                        Label("Add to Collection", systemImage: "square.stack")
                    }
                    if game.igdbID != nil {
                        Button {
                            Task { await repo.refreshFromIGDB(game) }
                        } label: {
                            Label("Refresh from IGDB", systemImage: "arrow.clockwise")
                        }
                    }
                    Divider()
                    Button {
                        playthroughName = "Playthrough \(game.livePlaythroughs.count + 1)"
                        namingNewPlaythrough = true
                    } label: {
                        Label("New Playthrough…", systemImage: "plus.square.on.square")
                    }
                    // Rename/Delete used to live ONLY in the playthrough picker,
                    // which appears at 2+ playthroughs — so with one, they were
                    // unreachable. Delete still needs a second one to fall back
                    // to, but Rename shouldn't have been hidden at all.
                    if game.activePlaythrough != nil {
                        Button {
                            playthroughName = game.activePlaythrough?.name ?? ""
                            renamingPlaythrough = true
                        } label: {
                            Label("Rename Playthrough…", systemImage: "pencil")
                        }
                    }
                    if game.livePlaythroughs.count > 1 {
                        Button(role: .destructive) {
                            confirmingPlaythroughDelete = true
                        } label: {
                            Label("Delete Playthrough…", systemImage: "trash.slash")
                        }
                    }
                    // Runs are a capability you switch on, not something the
                    // genre decides. Turning it off leaves existing runs in
                    // place, so it's never destructive.
                    Button {
                        let enabled = repo.runTrackingEnabled(for: game)
                        repo.setRunTracking(!enabled, for: game)
                    } label: {
                        Label(repo.runTrackingEnabled(for: game)
                                ? "Turn Off Run Logging" : "Log Runs for This Game",
                              systemImage: repo.runTrackingEnabled(for: game)
                                ? "flag.slash" : "flag.checkered")
                    }
                    Menu("Tracker Display") {
                        Button {
                            game.trackerDisplayRaw = nil
                        } label: {
                            Label("Follow Default (\(ThemePalette.defaultTrackerDisplay.label))",
                                  systemImage: game.trackerDisplayRaw == nil ? "checkmark" : "circle.dashed")
                        }
                        ForEach(TrackerDisplay.allCases, id: \.rawValue) { choice in
                            Button {
                                game.trackerDisplayRaw = choice.rawValue
                            } label: {
                                Label(choice.label, systemImage:
                                      game.trackerDisplayRaw == choice.rawValue ? "checkmark" : "circle")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Playthrough", isPresented: $namingNewPlaythrough) {
            TextField("Name", text: $playthroughName)
            Button("Create") {
                repo.addPlaythrough(to: game, named: playthroughName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fresh sessions and tracker progress. Your other playthroughs keep theirs.")
        }
        .alert("Rename Playthrough", isPresented: $renamingPlaythrough) {
            TextField("Name", text: $playthroughName)
            Button("Rename") {
                if let pt = game.activePlaythrough {
                    repo.renamePlaythrough(pt, to: playthroughName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(game.activePlaythrough?.name ?? "playthrough")?",
            isPresented: $confirmingPlaythroughDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Playthrough", role: .destructive) {
                if let pt = game.activePlaythrough {
                    repo.deletePlaythrough(pt, from: game)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sessions and tracker progress move to trash. A running session is stopped and recorded first.")
        }
        .confirmationDialog("Delete \(game.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Repository(context).softDelete(game)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves it to trash (recoverable).")
        }
    }

    // MARK: Playthrough picker (appears only with 2+)

    private var playthroughPicker: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(game.livePlaythroughs) { pt in
                    Button {
                        repo.setActivePlaythrough(pt, for: game)
                    } label: {
                        if pt.id == game.activePlaythrough?.id {
                            Label(pt.name, systemImage: "checkmark")
                        } else {
                            Text(pt.name)
                        }
                    }
                }
                Divider()
                Button {
                    playthroughName = "Playthrough \(game.livePlaythroughs.count + 1)"
                    namingNewPlaythrough = true
                } label: {
                    Label("New Playthrough…", systemImage: "plus")
                }
                Button {
                    playthroughName = game.activePlaythrough?.name ?? ""
                    renamingPlaythrough = true
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmingPlaythroughDelete = true
                } label: {
                    Label("Delete…", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.square.on.square.angled")
                        .font(.caption)
                    Text(game.activePlaythrough?.name ?? "Playthrough")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(LSTheme.accent.opacity(0.16), in: .capsule)
                .overlay(Capsule().strokeBorder(LSTheme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("\(game.livePlaythroughs.count) playthroughs")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Standard layout

    private func standardScroll(stageMode: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if game.livePlaythroughs.count > 1 {
                    playthroughPicker
                }
                Divider()
                CollapsibleSection("Sessions", icon: "stopwatch") {
                    SessionControlsView(game: game)
                }
                // Runs render in BOTH display modes. A run is a play-logging
                // action, the sibling of a session — and Sessions is right
                // above in compact too. Only the tracker *checklist* moves to
                // its own page in compact. Keeping Runs inside the inline-only
                // branch meant turning on "Log Runs for This Game" in compact
                // changed nothing you could see, so the menu item read as broken.
                if let template = game.trackerSchema.flatMap({
                    TrackerSchemaJSON.runTemplate(from: $0.jsonData)
                }) {
                    Divider()
                    CollapsibleSection("Runs", icon: "flag.checkered") {
                        RunSectionView(game: game, template: template)
                    }
                }
                Divider()
                CollapsibleSection("Tracker", icon: "checklist") {
                    if game.resolvedTrackerDisplay == .compact {
                        CompactTrackerCard(game: game, onOpen: stageMode ? { _ in stage = 2 } : nil)
                    } else {
                        TrackerSectionView(game: game)
                    }
                }
                Divider()
                CollapsibleSection("Guides & Videos", icon: "play.rectangle", defaultExpanded: false) {
                    VideoListView(game: game, playing: $pagePlaying)
                }
                Divider()
                if let summary = game.summary, !summary.isEmpty {
                    CollapsibleSection("About", icon: "text.alignleft", defaultExpanded: false) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
                CollapsibleSection("Game Info", icon: "info.circle", defaultExpanded: false) {
                    gameInfo
                }
                Divider()
                CollapsibleSection("Tags", icon: "tag", defaultExpanded: false) {
                    tagsEditor
                }
                Divider()
                CollapsibleSection("Review", icon: "star.bubble", defaultExpanded: false) {
                    reviewEditor
                }
                Divider()
                CollapsibleSection("Notes", icon: "note.text") {
                    notesField
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Sliding stage (iPad landscape / macOS, compact display)

    private func stageLayout(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            standardScroll(stageMode: true)
                .frame(width: stage == 1 ? width : width * 0.58)
                .offset(x: stage == 3 ? -width * 0.58 : 0)

            trackerPanel
                .frame(width: stage == 3 ? width * 0.46 : width * 0.42)
                .offset(x: stage == 1 ? width
                        : (stage == 2 ? width * 0.58 : 0))

            videoPanel
                .frame(width: width * 0.54)
                .offset(x: stage == 3 ? width * 0.46 : width * 1.02)
        }
        // The ZStack must span the FULL stage, not shrink to its widest child
        // — otherwise offset panels land outside the clip and vanish.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: stage)
        .clipped()
    }

    private var trackerPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(game.activePlaythrough?.name ?? "Playthrough")
                    .font(.subheadline.weight(.semibold))
                Text("tracker").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    stage = 3
                } label: {
                    Label("Videos", systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(LSTheme.accent)
                Button {
                    stage = 1
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .padding(6)
                        .background(.white.opacity(0.08), in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Runs deliberately do NOT render here. They used to, back
                    // when the compact branch of the game page had no Runs
                    // section at all and this panel was the only place to reach
                    // them. Now that Runs render in both display modes, the game
                    // page sitting beside this panel already shows them — and at
                    // stage 2 both are on screen at once, so repeating them here
                    // drew the section twice. This panel owns the tracker
                    // checklist alone, which is the split compact mode exists to
                    // express.
                    TrackerSectionView(game: game)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(LSTheme.accent.opacity(0.25)).frame(width: 1)
        }
    }

    private var videoPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Guides & Videos", systemImage: "play.rectangle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    stage = 2
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .padding(6)
                        .background(.white.opacity(0.08), in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            Divider()
            if let video = pagePlaying {
                VideoPlayerDock(video: video) { pagePlaying = nil }
            }
            ScrollView {
                VideoListView(game: game, playing: $pagePlaying)
                    .padding()
            }
            .scrollIndicators(.hidden)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(LSTheme.accent.opacity(0.25)).frame(width: 1)
        }
    }

    // MARK: Backdrop

    /// Ambient page background: the game's own cover, blurred and saturated,
    /// glowing behind the top of the page and fading into the app gradient —
    /// every game gets its own atmosphere.
    private var ambientBackdrop: some View {
        ZStack(alignment: .top) {
            LSTheme.background

            if ThemePalette.pageBackground == .status {
                // Status-color gradient variant (user-selectable in Appearance).
                LinearGradient(
                    colors: [game.status.color.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .center
                )
                .frame(height: 420)
                .frame(maxWidth: .infinity)
            } else if let s = game.coverURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 420)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .blur(radius: 60, opaque: true)
                            .saturation(1.5)
                            .opacity(0.55)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.6), location: 0.55),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                CoverThumb(urlString: game.coverURLString)
                    .frame(width: 138, height: 184)
                    .overlay { CoverShine(delay: 0.25) }
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .contentShape(.rect)
                    .onTapGesture { showingCover = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Enlarge cover")

                VStack(alignment: .leading, spacing: 8) {
                    Text(game.name)
                        .font(.title2.bold())

                    HStack(spacing: 6) {
                        Image(systemName: game.status.systemImage)
                            .foregroundStyle(game.status.color)
                        Text(game.status.label)
                        if let platform = PlatformPreference.sorted(game.platforms).first {
                            Text("·").foregroundStyle(.tertiary)
                            PlatformIconView(platform: platform, size: 20)
                            Text(PlatformShort.name(platform)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    RatingControl(rating: $game.rating)

                    if let franchise = game.franchise, !franchise.isEmpty {
                        Text(franchise)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Full-width so the three chips never wrap.
            OwnershipControl(ownership: $game.ownership)
        }
    }

    private var notesField: some View {
        TextField("Where you left off, thoughts, …", text: $game.notes, axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.roundedBorder)
    }

    // MARK: Game Info

    @State private var editingInfo = false

    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        editingInfo.toggle()
                    }
                } label: {
                    Label(editingInfo ? "Done" : "Edit",
                          systemImage: editingInfo ? "checkmark" : "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tint(LSTheme.accent)
            }

            if editingInfo {
                editForm
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        infoCell("Released", game.firstReleaseDate.map {
                            String(Calendar.current.component(.year, from: $0))
                        })
                        infoCell("Series", game.franchise)
                    }
                    GridRow {
                        infoCell("Developer", game.developers.first)
                        infoCell("Publisher", game.publishers.first)
                    }
                }

                if !game.platforms.isEmpty {
                    chipGroup("Platforms", game.platforms, tint: .blue)
                }
                let genreTheme = game.genres + game.themes
                if !genreTheme.isEmpty {
                    chipGroup("Genre / Theme", genreTheme, tint: LSTheme.accent)
                }
                if !game.gameModes.isEmpty {
                    chipGroup("Game Modes", game.gameModes, tint: .teal)
                }
                if !game.playerPerspectives.isEmpty {
                    chipGroup("Perspective", game.playerPerspectives, tint: .gray)
                }
            }

            HStack(spacing: 18) {
                Button {
                    browserTarget = DekuLinkTarget(url: DekuLinks.search(for: game.name))
                } label: {
                    Label("Deku Deals", systemImage: "tag.fill")
                }
                if let slug = game.igdbSlug,
                   let url = URL(string: "https://www.igdb.com/games/\(slug)") {
                    Button {
                        browserTarget = DekuLinkTarget(url: url)
                    } label: {
                        Label("IGDB", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
        }
    }

    /// Edit mode: everything IGDB filled in is overridable per game.
    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                labeledField("Released", text: Binding(
                    get: {
                        game.firstReleaseDate.map {
                            String(Calendar.current.component(.year, from: $0))
                        } ?? ""
                    },
                    set: { text in
                        if let year = Int(text), (1950..<3000).contains(year) {
                            game.firstReleaseDate = DateComponents(
                                calendar: .current, year: year, month: 1, day: 1).date
                        } else if text.isEmpty {
                            game.firstReleaseDate = nil
                        }
                    }
                ))
                labeledField("Series", text: Binding(
                    get: { game.franchise ?? "" },
                    set: { game.franchise = $0.isEmpty ? nil : $0 }
                ))
            }
            HStack(spacing: 12) {
                labeledField("Developer", text: firstElementBinding(\.developers))
                labeledField("Publisher", text: firstElementBinding(\.publishers))
            }
            PlatformEditor(platforms: $game.platforms)
            EditableChips(title: "Genres", values: $game.genres, tint: LSTheme.accent)
            EditableChips(title: "Themes", values: $game.themes, tint: LSTheme.accent)
            EditableChips(title: "Game Modes", values: $game.gameModes, tint: .teal)
            EditableChips(title: "Perspective", values: $game.playerPerspectives, tint: .gray)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }

    private func firstElementBinding(_ keyPath: ReferenceWritableKeyPath<Game, [String]>) -> Binding<String> {
        Binding(
            get: { game[keyPath: keyPath].first ?? "" },
            set: { value in
                var array = game[keyPath: keyPath]
                if value.isEmpty {
                    if !array.isEmpty { array.removeFirst() }
                } else if array.isEmpty {
                    array = [value]
                } else {
                    array[0] = value
                }
                game[keyPath: keyPath] = array
            }
        )
    }

    private func infoCell(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "—").font(.subheadline)
        }
        .gridColumnAlignment(.leading)
    }

    private func chipGroup(_ label: String, _ values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { Chip(text: $0, tint: tint) }
            }
        }
    }

    // MARK: Tags

    @State private var newTag = ""

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !game.userTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(game.userTags, id: \.self) { tag in
                        Chip(text: "#\(tag)", tint: LSTheme.accent) {
                            game.userTags.removeAll { $0 == tag }
                        }
                    }
                }
            }
            TextField("Add a tag…", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let tag = newTag
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "#", with: "")
                    if !tag.isEmpty, !game.userTags.contains(tag) {
                        game.userTags.append(tag)
                    }
                    newTag = ""
                }
        }
    }

    // MARK: Review

    private var reviewEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            RatingControl(rating: $game.rating)
            TextField("Your review…", text: Binding(
                get: { game.review ?? "" },
                set: { game.review = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.roundedBorder)
        }
    }
}
