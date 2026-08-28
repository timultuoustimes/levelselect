import SwiftUI
import SwiftData

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var fixingMatch = false
    /// Which artwork role the picker is open for, if any.
    @State private var pickingArtwork: ArtworkRole?
    /// Key art / screenshot for the header, resolved asynchronously. Nil
    /// until a lookup finishes (or when the library preference wants no
    /// fetched art at all), and the cover stands in meanwhile.
    @State private var backdropArt: URL?
    /// Library-wide reading preference, device-local like the Stats cards.
    @AppStorage("gameSectionOrder") private var sectionOrderRaw = ""
    @AppStorage("gameHiddenSections") private var hiddenSectionsRaw = ""
    @State private var browserTarget: DekuLinkTarget?
    @State private var markingBeaten = false
    @State private var editingOutcomeNote = false
    @State private var outcomeNoteDraft = ""

    @State private var pagePlaying: GameVideo?
    @State private var showingCover = false
    /// Whether the game's name has scrolled up behind the navigation bar.
    @State private var titleInBar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAutoRefresh = false
    @State private var entryFingerprint: Int?

    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil }, sort: \GameCollection.name)
    private var collections: [GameCollection]
    @State private var newCollection = false
    @State private var newCollectionName = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var nav = AppNavigator.shared
    /// Wide-screen sliding stage: 1 = game page, 2 = +tracker, 3 = tracker+videos.
    @State private var stage = 1

    // Playthrough management
    @State private var namingNewPlaythrough = false
    @State private var renamingPlaythrough = false
    @State private var playthroughName = ""
    @State private var confirmingPlaythroughDelete = false

    private var repo: Repository { Repository(context) }

    /// Whether this page is wide enough to hold its tracker beside it.
    private func isStage(_ size: CGSize) -> Bool {
        StageLayout.fits(size) && game.resolvedTrackerDisplay == .compact
    }

    /// The page reads its container inline, from a GeometryReader, and keeps
    /// nothing about its own size in state.
    ///
    /// Storing it seemed tidier and was worse: rotating away from the stage
    /// left the stored width behind, so a portrait phone went on rendering a
    /// landscape-width stage — content wider than the screen, shifted off the
    /// leading edge. Read inline, the size cannot be stale.
    ///
    /// The page ignores the bottom safe area so both stage panes reach the
    /// screen edge instead of stopping short of the tab bar (which left a
    /// band of bare background under the split). Everything that scrolls then
    /// needs that inset handed back explicitly — `contentMargins` below —
    /// because content under a bar you can't scroll past is worse than a band.
    var body: some View {
        GeometryReader { geo in
            let stageMode = isStage(geo.size)
            Group {
                if stageMode {
                    stageLayout(width: geo.size.width, topInset: geo.safeAreaInsets.top)
                } else {
                    VStack(spacing: 0) {
                        if let video = pagePlaying {
                            VideoPlayerDock(video: video) { pagePlaying = nil }
                        }
                        standardScroll(stageMode: false, topInset: geo.safeAreaInsets.top)
                    }
                }
            }
            // ORDER IS LOAD-BEARING. `ignoresSafeArea` lives HERE, inside the
            // GeometryReader, not on it. Applied outside, it consumed the
            // safe area before `geo` measured anything, so
            // `geo.safeAreaInsets.bottom` read 0 and the margin below added
            // nothing — the compensation this comment block describes has
            // never actually run. The last section (Notes) sat under the tab
            // bar with no way to scroll it clear, so its text field could not
            // be tapped at all. Measuring first, then ignoring, gives a real
            // inset to hand back.
            .ignoresSafeArea(.container, edges: .bottom)
            .contentMargins(.bottom, geo.safeAreaInsets.bottom, for: .scrollContent)
            // Watching `pagePlaying != nil` alone missed the rotation case
            // entirely: turn an iPad to landscape with a video ALREADY
            // playing and that boolean never changes, so `stage` stayed at 1
            // and the video panel sat at `width * 1.02` — off the trailing
            // edge, still playing, invisible. Both inputs decide the stage, so
            // both have to be observed.
            .onChange(of: pagePlaying != nil) { _, hasVideo in
                if stageMode, hasVideo { stage = 3 }
            }
            .onChange(of: stageMode) { _, isStage in
                if isStage, pagePlaying != nil { stage = 3 }
            }
            // A tracker page that dismissed itself because the stage became
            // available asks for its pane to be opened here.
            .task(id: stageMode) {
                guard stageMode, nav.trackerStageRequest == game.id else { return }
                nav.trackerStageRequest = nil
                stage = pagePlaying == nil ? 2 : 3
            }
        }
        .background { ambientBackdrop }
        .overlay {
            if showingCover {
                CoverShowcase(urlString: game.displayCoverURLString, isPresented: $showingCover)
            }
        }
        // Re-resolves when the game changes AND when the library preference
        // does, so switching between key art and screenshots in Settings
        // updates an open page rather than waiting for a revisit.
        .task(id: BackdropRequest(gameID: game.id, background: ThemePalette.pageBackground)) {
            guard ThemePalette.pageBackground.igdbEndpoint != nil else {
                backdropArt = nil
                return
            }
            backdropArt = await BackdropArt.url(for: game,
                                                preference: ThemePalette.pageBackground)
        }
        .task(id: showCriticScores) {
            // Only for people who asked to see it — which also means the
            // network call never happens for anyone who didn't.
            guard showCriticScores, let id = game.igdbID else { return }
            if let hit = GameReferenceService.shared.cached(id) {
                reference = hit
            } else {
                reference = await GameReferenceService.shared.load(id)
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
        .onAppear {
            // Fold any sync-duplicated rows for THIS game before its page
            // shows them. Bounded to one game, unlike the old whole-library
            // foreground sweep; a clean game writes nothing.
            repo.reconcile(game)
            // Move any note or rename still living inside the schema blob into
            // its own record, once. Idempotent, and a no-op for a game that
            // has none.
            repo.liftTrackerItemDetails(for: game)
            // Snapshot the binding-edited fields so leaving the page can tell
            // whether THIS game changed — not whether the context has any
            // pending change, which stamped the wrong game (or missed an
            // autosaved one).
            entryFingerprint = game.bindingEditFingerprint
        }
        .onDisappear {
            // The metadata, review and notes editors write through bindings on
            // every keystroke; this stamps sync metadata and commits once at
            // the natural boundary instead of per keystroke. No-op when the
            // visit changed nothing on this game.
            if let entryFingerprint {
                repo.finalizeEdits(game, ifChangedFrom: entryFingerprint)
            }
        }
        .dekuBrowser(target: $browserTarget)
        .alert("Why did it end?", isPresented: $editingOutcomeNote) {
            TextField("Optional — combat never clicked, lost the save…",
                      text: $outcomeNoteDraft)
            Button("Save") {
                if let pt = game.activePlaythrough {
                    repo.setPlaythroughOutcome(pt, outcome: pt.outcome,
                                               note: outcomeNoteDraft)
                }
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("The reason is the part worth keeping — a status on its own doesn't say what happened.")
        }
        .sheet(isPresented: $markingBeaten) {
            MarkCompletionSheet(game: game)
                #if !os(macOS)
                .presentationDetents([.medium, .large])
                #endif
        }
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
        // Still set, and still the real text: it names this screen for
        // VoiceOver, titles the Mac window, and labels the previous screen's
        // back button. Only the DRAWN title is swapped for the fading one
        // below.
        .navigationTitle(game.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if !os(macOS)
            ToolbarItem(placement: .principal) {
                // The game's name is already enormous in the header, as a logo
                // where one is set. Printing it again two inches above was
                // just noise; it earns its place in the bar only once the
                // header's copy has gone.
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(titleInBar ? 1 : 0)
                    // The bar title is redundant while the header shows the
                    // name, so it's hidden from VoiceOver too rather than
                    // being an invisible duplicate in the rotor.
                    .accessibilityHidden(!titleInBar)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                // Seven stable rows. This menu had grown to fifteen — library
                // classification, a completion workflow, metadata repair,
                // playthrough CRUD, a capability toggle, two per-game display
                // overrides, a device-wide layout preference, artwork and
                // deletion — ordered by the build each one landed in, and long
                // enough to scroll at standard text. Opening it no longer
                // answered a stable question.
                //
                // The rule now: this menu is about the GAME as an object. A
                // per-game display override lives in the section it affects;
                // a library-wide default lives in Settings; fetched metadata
                // lives under Game information.
                Menu {
                    Button {
                        repo.edit(game) { $0.pinned.toggle() }
                    } label: {
                        Label(game.pinned ? "Unpin" : "Pin", systemImage: game.pinned ? "pin.slash" : "pin")
                    }
                    // A Picker, not nine Buttons with a hand-drawn checkmark.
                    // Completed's own glyph is `checkmark.circle.fill`, which
                    // VoiceOver read as a second selected row — so the current
                    // status was ambiguous to anyone not looking at it. The
                    // value goes in the label too: "Status" alone made you open
                    // the menu to find out what the status was.
                    Menu {
                        Picker("Status", selection: statusBinding) {
                            ForEach(GameStatus.displayOrder, id: \.self) { s in
                                Label(s.label, systemImage: s.systemImage).tag(s)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Status: \(game.status.label)", systemImage: game.status.systemImage)
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
                        // Not "Add to Collection": tapping a checked row REMOVES
                        // the game, and the last row creates a collection. The
                        // label is the promise made before the tap.
                        Label("Collections", systemImage: "square.stack")
                    }
                    Divider()
                    Menu {
                        playthroughActions(includeNew: true)
                    } label: {
                        Label("Playthrough", systemImage: "person.crop.square.on.square.angled")
                    }
                    Menu {
                        ForEach(ArtworkRole.assignable) { role in
                            Button {
                                pickingArtwork = role
                            } label: {
                                Label(game.pointer(for: role) == nil
                                      ? "Choose \(role.label)…"
                                      : "Change \(role.label)…",
                                      systemImage: game.pointer(for: role) == nil
                                      ? "photo.on.rectangle.angled" : "checkmark")
                            }
                        }
                    } label: {
                        Label("Artwork", systemImage: "photo.on.rectangle.angled")
                    }
                    Menu {
                        if game.igdbID != nil {
                            Button {
                                Task { await repo.refreshFromIGDB(game) }
                            } label: {
                                Label("Refresh from IGDB", systemImage: "arrow.clockwise")
                            }
                        }
                        Button {
                            fixingMatch = true
                        } label: {
                            // "Fix Match" was our word for it, not the user's.
                            Label("Correct game match…", systemImage: "link.badge.plus")
                        }
                    } label: {
                        Label("Game information", systemImage: "info.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Game…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Game actions")
            }
        }
        .sheet(isPresented: $fixingMatch) {
            FixMatchView(game: game)
        }
        .sheet(item: $pickingArtwork) { role in
            ArtworkPickerView(game: game, role: role)
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

    private var statusBinding: Binding<GameStatus> {
        Binding(
            get: { game.status },
            set: { newValue in repo.edit(game) { $0.status = newValue } }
        )
    }

    /// The one description of what you can do to a playthrough, rendered in
    /// both the `⋯` menu and the switcher capsule.
    ///
    /// These used to be two separate lists, which meant the action model
    /// changed shape with the data: with one playthrough the switcher didn't
    /// exist, so **How it ended** — the most notebook-like field here, the
    /// place you say a run was dropped or a save was lost — was unreachable.
    /// With two, New/Rename/Delete appeared in both menus at once. A person
    /// could learn one route, start a second playthrough, and find a second
    /// competing surface.
    ///
    /// `includeNew` is false only where the caller has already promoted
    /// **New Playthrough…** above the list.
    @ViewBuilder
    private func playthroughActions(includeNew: Bool) -> some View {
        if includeNew {
            Button {
                playthroughName = "Playthrough \(game.livePlaythroughs.count + 1)"
                namingNewPlaythrough = true
            } label: {
                Label("New Playthrough…", systemImage: "plus")
            }
        }
        if let active = game.activePlaythrough {
            Button {
                playthroughName = active.name
                renamingPlaythrough = true
            } label: {
                // Naming the playthrough saves you opening the sheet to find
                // out which one you're about to rename.
                Label("Rename “\(active.name)”…", systemImage: "pencil")
            }
            Menu {
                Button {
                    repo.setPlaythroughOutcome(active, outcome: nil, note: nil)
                } label: {
                    Label("Still going", systemImage: active.outcome == nil
                          ? "checkmark" : "play.circle")
                }
                ForEach(PlaythroughOutcome.allCases, id: \.self) { choice in
                    Button {
                        repo.setPlaythroughOutcome(active, outcome: choice, note: active.outcomeNote)
                        outcomeNoteDraft = active.outcomeNote ?? ""
                        editingOutcomeNote = true
                    } label: {
                        Label(choice.label, systemImage: active.outcome == choice
                              ? "checkmark" : choice.systemImage)
                    }
                }
            } label: {
                Label("How it ended", systemImage: "flag.checkered")
            }
        }
        // Deleting the only playthrough would leave the game's sessions and
        // tracker progress with nowhere to live, so it stays conditional.
        if game.livePlaythroughs.count > 1 {
            Button(role: .destructive) {
                confirmingPlaythroughDelete = true
            } label: {
                Label("Delete Playthrough…", systemImage: "trash")
            }
        }
    }

    private var playthroughPicker: some View {
        // Same overflow rule as the hero: capsule plus caption can outgrow
        // the screen at accessibility sizes, so they stack instead.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        let activeFinished = game.activePlaythrough?.isFinished == true
        return layout {
            Menu {
                // A finished run shouldn't be the path of least resistance:
                // when the current one is done, starting fresh leads. It moves
                // ABOVE the list rather than appearing a second time — this
                // menu used to render "New Playthrough…" twice whenever the
                // active one was finished.
                if activeFinished {
                    Button {
                        playthroughName = "Playthrough \(game.livePlaythroughs.count + 1)"
                        namingNewPlaythrough = true
                    } label: {
                        Label("New Playthrough…", systemImage: "plus")
                    }
                    Divider()
                }
                ForEach(game.livePlaythroughs) { pt in
                    Button {
                        repo.setActivePlaythrough(pt, for: game)
                    } label: {
                        let title = pt.isFinished ? "\(pt.name) — finished" : pt.name
                        if pt.id == game.activePlaythrough?.id {
                            Label(title, systemImage: "checkmark")
                        } else if pt.isFinished {
                            Label(title, systemImage: "flag.checkered")
                        } else {
                            Text(title)
                        }
                    }
                }
                Divider()
                playthroughActions(includeNew: !activeFinished)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.square.on.square.angled")
                        .font(.caption)
                    Text(game.activePlaythrough?.name ?? "Playthrough")
                        .font(.subheadline.weight(.semibold))
                    if activeFinished {
                        Image(systemName: "flag.checkered")
                            .font(.caption2)
                            .accessibilityLabel("Finished")
                    }
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

    /// Sections that render for THIS game right now: the arranged order,
    /// minus hidden ones, minus sections that are absent anyway (Runs with
    /// no template, About with no summary). Absence and hiding are different
    /// problems — conflating them is the empty-menu bug pattern.
    private var visibleSections: [GamePageSection] {
        GamePageSection.resolveOrder(stored: sectionOrderRaw).filter { section in
            if GamePageSection.hiddenSet(stored: hiddenSectionsRaw).contains(section) { return false }
            switch section {
            case .runs:  return runTemplate != nil
            case .about: return !(game.summary ?? "").isEmpty
            case .media: return game.igdbID != nil
            default:     return true
            }
        }
    }

    private var runTemplate: RunTemplateDTO? {
        game.trackerSchema.flatMap { TrackerSchemaJSON.runTemplate(from: $0.jsonData) }
    }

    /// One game-page section, collapse state scoped to this game — the
    /// title-only key collapsed a section on every game at once.
    @ViewBuilder
    private func sectionView(_ section: GamePageSection, stageMode: Bool) -> some View {
        let scope = game.id.uuidString
        switch section {
        case .sessions:
            CollapsibleSection("Sessions", icon: "stopwatch", scope: scope) {
                SessionControlsView(game: game)
            }
        case .beaten:
            CollapsibleSection("Beaten", icon: "flag.checkered",
                               defaultExpanded: false, scope: scope) {
                CompletionSection(game: game)
            }
        case .runs:
            // Runs render in BOTH display modes. A run is a play-logging
            // action, the sibling of a session — and Sessions is right
            // above in compact too. Only the tracker *checklist* moves to
            // its own page in compact. Keeping Runs inside the inline-only
            // branch meant turning on "Log Runs for This Game" in compact
            // changed nothing you could see, so the menu item read as broken.
            if let template = runTemplate {
                CollapsibleSection("Runs", icon: "arrow.2.squarepath", scope: scope) {
                    RunSectionView(game: game, template: template)
                }
            }
        case .tracker:
            CollapsibleSection("Tracker", icon: "checklist", scope: scope) {
                // Above both display modes: the question "what was I
                // doing?" is the same one whether the checklist is inline
                // or behind a card.
                LastTickedRow(game: game)
                if game.resolvedTrackerDisplay == .compact {
                    CompactTrackerCard(game: game, onOpen: stageMode ? { _ in stage = 2 } : nil)
                } else {
                    TrackerSectionView(game: game)
                }
            }
        case .videos:
            CollapsibleSection("Guides & Videos", icon: "play.rectangle",
                               defaultExpanded: false, scope: scope) {
                VideoListView(game: game, playing: $pagePlaying)
            }
        case .about:
            CollapsibleSection("About", icon: "text.alignleft",
                               defaultExpanded: false, scope: scope) {
                Text(game.summary ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .media:
            // Collapsed by default: the strip fetches only when rendered, so
            // a closed section spends no proxy quota.
            CollapsibleSection("Media", icon: "photo.stack",
                               defaultExpanded: false, scope: scope) {
                ScreenshotStrip(game: game)
            }
        case .info:
            CollapsibleSection("Game Info", icon: "info.circle",
                               defaultExpanded: false, scope: scope) {
                gameInfo
            }
        case .connections:
            CollapsibleSection("Connections", icon: "point.3.connected.trianglepath.dotted",
                               defaultExpanded: false, scope: scope) {
                RelatedGamesSection(game: game)
            }
        case .tags:
            CollapsibleSection("Tags", icon: "tag", defaultExpanded: false, scope: scope) {
                tagsEditor
            }
        case .review:
            CollapsibleSection("Review", icon: "star.bubble",
                               defaultExpanded: false, scope: scope) {
                reviewEditor
            }
        case .notes:
            CollapsibleSection("Notes", icon: "note.text", scope: scope) {
                notesField
            }
        }
    }

    private func standardScroll(stageMode: Bool, topInset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if game.livePlaythroughs.count > 1 {
                    playthroughPicker
                }
                ForEach(visibleSections) { section in
                    Divider()
                    sectionView(section, stageMode: stageMode)
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            // The backdrop hangs off the FULL-width frame, not the 640pt
            // reading column, so it reaches both screen edges on iPad and Mac
            // while the text stays in its column.
            .frame(maxWidth: .infinity)
            .background(alignment: .top) { scrollingBackdrop(topInset: topInset) }
        }
        .scrollIndicators(.hidden)
        // The handoff point is the header card's own title. Below it the name
        // is on screen in full; above it, the bar takes over.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let handedOver = offset > Self.heroTopSpace + Self.coverHeight + Self.titleBand
            guard handedOver != titleInBar else { return }
            // Reduce Motion gets the same handoff without the crossfade — the
            // information is the point, the fade is decoration.
            if reduceMotion {
                titleInBar = handedOver
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { titleInBar = handedOver }
            }
        }
    }

    /// The header art, drawn inside the scroll so it scrolls away with the
    /// header, and pulled up under the navigation bar so the page reads as one
    /// image with glass chrome floating on it.
    @ViewBuilder
    private func scrollingBackdrop(topInset: CGFloat) -> some View {
        switch ThemePalette.pageBackground {
        case .cover, .keyArt, .screenshot:
            // Grown upward by the safe-area inset and pulled up by the same
            // amount, so at rest the art fills the space behind the status bar
            // and the glass chrome — `ignoresSafeArea` can't do this from
            // inside a ScrollView, whose content origin already sits below the
            // bar. It stays scroll content, so it still travels away with the
            // header instead of sitting under the sections.
            coverBackdrop(extraTop: topInset)
                .padding(.top, -topInset)
        case .plain, .accent, .status:
            EmptyView()
        }
    }

    // MARK: Sliding stage (iPad landscape / macOS, compact display)

    private func stageLayout(width: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            standardScroll(stageMode: true, topInset: topInset)
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
                if stage == 3 {
                    stageTimerControl
                } else {
                    // At stage 3 this button is a no-op (videos are already
                    // open beside us), and the timer needs the room.
                    Button {
                        stage = 3
                    } label: {
                        Label("Videos", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(LSTheme.accent)
                }
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

    /// Compact timer for the tracker panel, shown only at stage 3.
    ///
    /// Stage 3 is the one arrangement where the game page — and with it the
    /// Sessions section — has slid off screen, yet it's also the arrangement
    /// you're in while actually playing: a guide video on one side, the
    /// checklist on the other. Without this you'd have to collapse the whole
    /// stage back to 1 just to stop the clock. Deliberately absent at stages 1
    /// and 2, where the full controls are already on screen beside this panel
    /// and a second set would just be two timers arguing.
    @ViewBuilder
    private var stageTimerControl: some View {
        if let active = game.activePlaythrough?.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.clock(active.elapsed(asOf: ctx.date)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .foregroundStyle(active.state == .running
                                     ? AnyShapeStyle(LSTheme.accent)
                                     : AnyShapeStyle(.secondary))
            }
            Button {
                if active.state == .running {
                    repo.pauseSession(active)
                } else {
                    repo.resumeSession(active)
                }
            } label: {
                Image(systemName: active.state == .running ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(.white.opacity(0.08), in: .circle)
            }
            .buttonStyle(.plain)
            Button {
                repo.stopSession(active)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(.white.opacity(0.08), in: .circle)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.startSession(on: pt)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(LSTheme.accent)
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

            switch ThemePalette.pageBackground {
            case .plain:
                // Quiet page — some notebooks are ruled paper, not collage.
                EmptyView()
            case .status:
                // Status-color gradient variant (user-selectable in Appearance).
                LinearGradient(
                    colors: [game.status.color.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .center
                )
                .frame(height: 420)
                .frame(maxWidth: .infinity)
            case .accent:
                LinearGradient(
                    colors: [LSTheme.accent.opacity(0.40), .clear],
                    startPoint: .top, endPoint: .center
                )
                .frame(height: 420)
                .frame(maxWidth: .infinity)
            case .cover, .keyArt, .screenshot:
                // Nothing here. The art moved INTO the scroll (see
                // `standardScroll`) so it travels with the header it belongs
                // to. Pinned behind the whole page, it used to sit under the
                // section list — survivable while the art was faded to 22%
                // by mid-page, unreadable once the header redesign let it
                // hold full strength. A backdrop is part of the header, not
                // wallpaper for the document.
                EmptyView()
            }
        }
        .ignoresSafeArea()
    }

    /// The art behind the header.
    ///
    /// Prefers whatever the backdrop role resolves to — which is a chosen
    /// image, else an IGDB artwork, else the cover. That order matters more
    /// than the blur does: a 3:4 cover scaled to fill a 420pt band gets
    /// cropped to a narrow horizontal slice of its middle, usually the least
    /// characteristic part of it. Artworks are 16:9 and drawn to be
    /// backgrounds, and the app was already fetching them and doing nothing
    /// with them.
    /// What the backdrop should actually draw.
    ///
    /// A per-game choice (local bytes or an explicit URL) wins outright.
    /// Otherwise it's the fetched key art or screenshot once `backdropArt`
    /// resolves, and the cover until then — so the header is never empty
    /// while a lookup is in flight, it just improves when the art lands.
    private var backdropArtwork: ResolvedArtwork {
        if game.pointer(for: .backdrop) != nil {
            return game.resolvedArtwork(.backdrop)
        }
        if let fetched = backdropArt { return .remote(fetched) }
        return game.resolvedArtwork(.cover)
    }

    @ViewBuilder
    private func coverBackdrop(extraTop: CGFloat = 0) -> some View {
        let intensity = ThemePalette.backdropIntensity
        if intensity != .off {
            ArtworkView(backdropArtwork)
                .frame(height: 420 + extraTop)
                .frame(maxWidth: .infinity)
                .clipped()
                .blur(radius: intensity.blurRadius, opaque: true)
                .saturation(intensity.saturation)
                .opacity(intensity.opacity)
                // The falloff used to be brutal — 22% left by 45% down the
                // page — because the hero's text sat directly on this image
                // and had to stay readable over key art. It doesn't any more:
                // the text moved onto a material card in front. So the art
                // holds full strength through the band you actually see it
                // in, and fades where the page's own sections take over.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.42),
                            .init(color: .black.opacity(0.55), location: 0.62),
                            .init(color: .clear, location: 0.92),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: Sections

    private static let coverWidth: CGFloat = 132
    private static var coverHeight: CGFloat { coverWidth * 4 / 3 }
    /// Bare art above the cover, so the header opens on the image rather than
    /// on a box.
    private static let heroTopSpace: CGFloat = 18
    /// The band the title occupies, below the cover and the facts panel.
    private static let titleBand: CGFloat = 120

    /// The header.
    ///
    /// The old one laid the game's name, status, rating and chips directly on
    /// the backdrop, which is why the backdrop had to be beaten into
    /// illegibility to keep them readable — a 60pt blur and a mask that killed
    /// the art by 45% down the page. You could change the image and not be
    /// able to tell.
    ///
    /// The shape is Tim's: the cover and a narrow facts panel sit side by side
    /// in the art, and the game's name runs underneath them both, centred and
    /// large. An earlier pass had the name beside the cover on a full-width
    /// card it half-overlapped, which gave the title only the column left over
    /// after a 132pt cover — so a wordmark that is the most recognisable thing
    /// about a game got the smallest space on the page. Below, it gets the
    /// whole width.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: Self.heroTopSpace)

            if stacksCover {
                VStack(alignment: .leading, spacing: 12) {
                    coverThumb(width: Self.coverWidth)
                    factsPanel(fills: true)
                }
            } else {
                // Two spacers, so the pair is CENTRED rather than left-flush.
                //
                // The panel takes the width its words need — without that it
                // stretched to the page margin and carried a stripe of empty
                // haze past the end of its own longest line. But hugging on
                // the right alone left the pair ending short of the margin
                // while the title beneath it was centred, so the header held
                // two different alignments at once and the artwork looked
                // shunted to one side.
                //
                // The art band is its own zone: cover, panel and title all
                // centre in it. The chips and stats below sit on the page and
                // stay left-aligned, which is a different register, not an
                // inconsistency.
                //
                // Both spacers collapse to nothing when space is tight, so a
                // long platform name still gets the room.
                HStack(alignment: .top, spacing: 10) {
                    Spacer(minLength: 0)
                    coverThumb(width: Self.coverWidth)
                    factsPanel(fills: false)
                        // Dropped slightly so the panel reads as sitting
                        // against the cover rather than being ruled off level
                        // with it.
                        .padding(.top, 26)
                        // Spacers are greedy and text is compressible, so
                        // without this the two of them split the row with the
                        // panel and wrapped "Now Playing" onto a second line.
                        // The panel is measured first; the spacers divide
                        // what's actually left.
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
            }

            heroTitle

            // Full-width, below the art: four chips and a stats row both want
            // the whole column, and neither is something you read at a glance
            // the way the title is.
            OwnershipControl(ownership: $game.ownership, centered: true)

            if showGameStats {
                GameStatsRow(game: game, showsRuns: repo.runTrackingEnabled(for: game))
            }
        }
    }

    /// What this game is to you: where it sits, what you scored it, what the
    /// critics said. Everything here is words, which is why it's on a panel
    /// and not on the art.
    /// `fills` is true only where the panel is alone on its row (accessibility
    /// sizes), where hugging its content would leave it stranded mid-page.
    private func factsPanel(fills: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: game.status.systemImage)
                    .foregroundStyle(game.status.color)
                Text(game.status.label)
                if let platform = PlatformPreference.owned(game.platforms) {
                    Text("·").foregroundStyle(.tertiary)
                    PlatformIconView(platform: platform, size: 20)
                    Text(PlatformShort.name(platform)).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            // This line sets the panel's width, so it must not be willing to
            // wrap: a wrapping Text answers a narrow proposal by growing
            // taller instead of asking for more room, so the panel settled
            // small and the centring spacers pocketed the difference — which
            // is how "Now Playing" ended up on two lines inside a panel with
            // space to spare. One line makes its ideal width honest, which is
            // what `layoutPriority` on the panel then acts on.
            //
            // NOT `fixedSize`: that makes the width a demand rather than a
            // preference, and the panel pushed the whole page column wider
            // than the screen — every section divider below ran off the right
            // edge. Scaling is the give of last resort, for the rare platform
            // `PlatformShort` has no abbreviation for.
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            RatingControl(rating: $game.rating)

            // Directly under your own verdict, because the comparison is the
            // entire point — a critic score parked elsewhere on the page is
            // just trivia.
            referenceRow

            if let franchise = game.franchise, !franchise.isEmpty {
                Text(franchise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }

    /// The game's name across the full width — as its logo when one is set, as
    /// large text otherwise.
    ///
    /// Text is not a degraded fallback here, it's the default, and it comes
    /// BACK at accessibility type sizes: a logo is an image of text, it can't
    /// grow with Dynamic Type, and a fixed wordmark beside 60pt body copy
    /// reads as broken. The navigation title stays real text regardless, so
    /// VoiceOver, the back button and the Mac window title are unaffected.
    @ViewBuilder
    private var heroTitle: some View {
        let artwork = game.resolvedArtwork(.logo)
        if !artwork.isEmpty, !typeSize.isAccessibilitySize {
            ArtworkView(artwork, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: Self.titleBand)
                .accessibilityLabel(game.name)
        } else {
            Text(game.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // Unlike the panel's copy, this sits directly on the art. It
                // survives there because it's large and heavy — but a bright
                // screenshot can still swallow white text, so it carries its
                // own shadow rather than trusting the backdrop to be dark.
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        }
    }

    private func coverThumb(width: CGFloat) -> some View {
        CoverThumb(urlString: game.displayCoverURLString)
            .frame(width: width, height: width * 4 / 3)
            .overlay { CoverShine(delay: 0.25) }
            .clipShape(.rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
            .contentShape(.rect)
            .onTapGesture { showingCover = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Enlarge cover")
    }

    /// At accessibility text sizes the cover-beside-text row can't fit its own
    /// minimums, and one over-wide child drags the whole page's column
    /// offscreen with it.
    private var stacksCover: Bool { typeSize.isAccessibilitySize }

    private var notesField: some View {
        TextField("Where you left off, thoughts, …", text: $game.notes, axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.roundedBorder)
    }

    // MARK: Game Info

    @State private var editingInfo = false
    /// Off unless asked for: someone who hasn't opted in shouldn't find a
    /// critic's number sitting next to their own opinion. Device-local — it's
    /// a display preference, and storing it would be a Schema V3 for a toggle.
    @AppStorage("showCriticScores") private var showCriticScores = false
    /// Whether the game stats cards appear at the top of every game page.
    ///
    /// Timing your play is opt-in in this app, and plenty of people log a
    /// library without ever starting a timer. A permanent "0s played / 0
    /// sessions" card is a reproach to those people on every game they own,
    /// so the row can be switched off — device-local, like the rest of the
    /// game page's layout preferences.
    @AppStorage("gamePageShowStats") private var showGameStats = true
    @State private var reference: GameReferenceService.Reference?

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
                    // Every one of these is really a set of games rather than
                    // a fact about this one, so each is a way into the library
                    // filtered to it.
                    GridRow {
                        infoCell("Released", game.firstReleaseDate.map {
                            String(Calendar.current.component(.year, from: $0))
                        }, kind: .year)
                        infoCell("Series", game.franchise, kind: .franchise)
                    }
                    GridRow {
                        infoCell("Developer", game.developers.first, kind: .developer)
                        infoCell("Publisher", game.publishers.first, kind: .publisher)
                    }
                }

                if !game.platforms.isEmpty {
                    platformsGroup
                }
                if !game.genres.isEmpty || !game.themes.isEmpty {
                    facetChips("Genre / Theme",
                               game.genres.map { GameFacet(kind: .genre, value: $0) }
                             + game.themes.map { GameFacet(kind: .theme, value: $0) },
                               tint: LSTheme.accent)
                }
                if !game.gameModes.isEmpty {
                    facetChips("Game Modes",
                               game.gameModes.map { GameFacet(kind: .mode, value: $0) },
                               tint: .teal)
                }
                if !game.playerPerspectives.isEmpty {
                    facetChips("Perspective",
                               game.playerPerspectives.map { GameFacet(kind: .perspective, value: $0) },
                               tint: .gray)
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
                if let raID = game.trackerSchema.flatMap({
                    TrackerSchemaJSON.retroAchievementsGameID(in: $0.jsonData)
                }) {
                    Button {
                        browserTarget = DekuLinkTarget(url: RAArt.gamePage(raID))
                    } label: {
                        Label("RetroAchievements", systemImage: "trophy.fill")
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

    /// A labelled value, tappable when there's a slice of the library behind
    /// it. Styled the same either way — the panel is a reference table first,
    /// and making every field look like a button would turn it into a menu.
    @ViewBuilder
    private func infoCell(_ label: String, _ value: String?,
                          kind: GameFacet.Kind? = nil) -> some View {
        let text = value?.isEmpty == false ? value! : nil
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let text, let kind {
                FacetLink(facet: GameFacet(kind: kind, value: text)) {
                    HStack(spacing: 3) {
                        Text(text).font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(text ?? "—").font(.subheadline)
            }
        }
        .gridColumnAlignment(.leading)
    }

    /// Chips that lead somewhere.
    private func facetChips(_ label: String, _ facets: [GameFacet], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(facets, id: \.self) { facet in
                    FacetLink(facet: facet) { Chip(text: facet.value, tint: tint) }
                }
            }
        }
    }

    /// Critic score and typical completion time, when they're solid enough to
    /// show and the user asked to see them.
    ///
    /// The scales aren't reconciled on purpose. Your rating is five stars and
    /// theirs is out of a hundred; normalising either would invent a precision
    /// neither has. They sit next to each other and the reader does the work.
    @ViewBuilder
    private var referenceRow: some View {
        if showCriticScores, let reference, !reference.isEmpty {
            HStack(spacing: 12) {
                if let score = reference.criticScore {
                    HStack(spacing: 4) {
                        // "/100" and a named count, because "85 critics (23)"
                        // reads as a tally of critics rather than a score out
                        // of a hundred agreed by 23 of them.
                        Text("\(score)/100")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(LSTheme.accent)
                        Text(reference.criticSources == 1
                             ? "· 1 critic review"
                             : "· \(reference.criticSources) critic reviews")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let normally = reference.normally {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("~\(Format.hours(normally))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(reference.timeReports == 1
                             ? "· 1 time report"
                             : "· \(reference.timeReports) time reports")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Platforms, with yours marked.
    ///
    /// Seeing every platform a game shipped on is useful — it's how you notice
    /// there's a Switch port. But the one you own is the one that's *yours*,
    /// and an undifferentiated row of three said nothing about which.
    private var platformsGroup: some View {
        let mine = PlatformPreference.owned(game.platforms)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Platforms").font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(game.platforms, id: \.self) { platform in
                    if platform == mine {
                        HStack(spacing: 5) {
                            PlatformIconView(platform: platform, size: 14)
                            Text(platform)
                            Text("MINE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(LSTheme.accent)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(LSTheme.accent.opacity(0.18), in: .capsule)
                        .overlay(Capsule().strokeBorder(LSTheme.accent.opacity(0.55), lineWidth: 1))
                    } else {
                        Chip(text: platform, tint: .blue)
                    }
                }
            }
        }
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
                            repo.edit(game) { $0.userTags.removeAll { $0 == tag } }
                        }
                    }
                }
            }
            TextField("Add a tag…", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addTag(newTag) }
            // Suggest from the library's own vocabulary as you type. This is
            // what keeps `roguelike` from fragmenting into `rogue-like` and
            // `Roguelike` — the split that quietly kills tagging. No model,
            // no network: just the words you've already used.
            if !tagSuggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button { addTag(tag) } label: {
                            Chip(text: "#\(tag)", tint: .gray)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add tag \(tag)")
                    }
                }
            }
        }
    }

    private var tagSuggestions: [String] {
        let typed = newTag
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard !typed.isEmpty else { return [] }
        return repo.tagCounts()
            .map(\.tag)
            .filter { candidate in
                // A candidate differing only in case IS offered — tapping it
                // adopts the existing spelling instead of minting a variant.
                !game.userTags.contains(candidate)
                && candidate != typed
                && candidate.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            .prefix(6)
            .map { $0 }
    }

    private func addTag(_ raw: String) {
        let tag = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        if !tag.isEmpty, !game.userTags.contains(tag) {
            repo.edit(game) { $0.userTags.append(tag) }
        }
        newTag = ""
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
