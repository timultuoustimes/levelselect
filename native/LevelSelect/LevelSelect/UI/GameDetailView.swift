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
    /// Automatically-found wordmark, when the user hasn't chosen one.
    @State private var fetchedLogo: URL?
    /// Library-wide reading preference, device-local like the Stats cards.
    @State private var showingPageSettings = false
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
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
        .task(id: game.id) {
            // Only ever consulted when there's no explicit choice, and it
            // caches misses, so a game with no logo anywhere costs one lookup
            // for the life of the install.
            fetchedLogo = await LogoArt.url(for: game)
        }
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
                .lsSheet()
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
                    // Named for what someone is looking for, not for its scope
                    // — the sheet's own title carries the scope. Tim: *"Game
                    // page settings seems like the better choice right now."*
                    Button {
                        showingPageSettings = true
                    } label: {
                        Label("Game page settings…", systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Game…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        // **A control you cannot find is not a control.**
                        //
                        // Over Sonic 2's red key art the glass ring reads as a
                        // faint outline you would only find if you knew it was
                        // there. Liquid Glass borrows its contrast from what is
                        // behind it, and bright art has none to lend. Fable,
                        // 2026-09-07.
                        //
                        // **Only where there is art, and no measuring.** Fable
                        // proposed sampling the backdrop's luminance and
                        // fading a scrim in when it is light. Same outcome for
                        // a fraction of the cost: a dark scrim over a dark
                        // backdrop is invisible, and over a bright one it is
                        // the thing that saves the control — so the only
                        // question worth asking is whether art is under the
                        // bar at all. Sampling would mean decoding a remote
                        // image, caching the result, and re-running it when
                        // the art changes, to learn something the scrim
                        // already handles by being dark.
                        //
                        // On a page with no backdrop the bar sits on the page
                        // ground, where the glass works as designed and a
                        // plate would be the only thing you noticed.
                        .lsToolbarScrim(over: !backdropArtwork.isEmpty)
                }
                .accessibilityLabel("Game actions")
            }
        }
        .sheet(isPresented: $fixingMatch) {
            FixMatchView(game: game).lsSheet()
        }
        .sheet(isPresented: $showingPageSettings) {
            GamePageSettingsSheet().lsSheet()
        }
        .sheet(item: $pickingArtwork) { role in
            ArtworkPickerView(game: game, role: role).lsSheet()
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
                // Captured BEFORE the delete: after it, the row is tombstoned
                // and this view is being dismissed.
                let undo = AppNavigator.DeletedGame(id: game.id, name: game.name)
                Repository(context).softDelete(game)
                AppNavigator.shared.deletedGame = undo
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently Deleted, with its sessions and progress. You can put it back for 30 days — or undo right away.")
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

    /// One section's open state: the synced library default, overridden by
    /// anything this game disagrees about, written back to the game.
    private func expansion(_ section: GamePageSection) -> Binding<Bool> {
        let defaults = GamePageSection.defaultExpanded(stored: themeSettings.first?.expandedSectionsRaw)
        return Binding(
            get: {
                GamePageSection.isExpanded(section, defaults: defaults,
                                           overrides: game.sectionStateRaw)
            },
            set: { open in
                game.sectionStateRaw = GamePageSection.writingOverride(
                    section, open: open, into: game.sectionStateRaw, defaults: defaults)
                game.updatedAt = .now
            })
    }

    /// **Which sections open on arrival, and why the reference ones do not.**
    ///
    /// The rule shipped as "open when it has something in it", and Tim caught
    /// that it did not describe what the page does: *"all games pull info from
    /// igdb and have things in them and none of them start expanded except for
    /// tracker and Notes."* He was right twice over — About, Game Info and
    /// Connections were still pinned `defaultExpanded: false` from before, so
    /// the rule could never reach them; and had it reached them, every game
    /// page would open with a wall of IGDB prose, a metadata table and two
    /// carousels, on every game, identically.
    ///
    /// So the rule is narrower and says something true: **a section opens when
    /// it holds something YOU put there.** Sessions, Beaten, Runs, Tags,
    /// Review — those are your record of this game, and differ game to game.
    /// About, Game Info, Connections and Media are IGDB's, the same shape on
    /// every game, and are reference you go to rather than history you arrive
    /// at. They still light their glyph and still carry a caption, so a closed
    /// row tells you they are there and what is in them.
    ///
    /// Tracker and Notes open even when empty, because their empty state is a
    /// control rather than an absence.

    /// **What a closed section holds, in a few words.**
    ///
    /// Fable's 5.6: the page below the hero was twelve identical gray rows, so
    /// the only way to learn whether a section had anything in it was to open
    /// all twelve. Nil here means genuinely empty — and `CollapsibleSection`
    /// reads that one signal three ways: no caption, a gray glyph instead of
    /// an accent one, and closed on first sight.
    private func caption(for section: GamePageSection) -> String? {
        func plural(_ n: Int, _ one: String, _ many: String) -> String? {
            n == 0 ? nil : "\(n) \(n == 1 ? one : many)"
        }
        switch section {
        case .sessions:
            let played = game.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }
            let count = game.livePlaythroughs.reduce(0) { $0 + ($1.sessions ?? []).filter { $0.deletedAt == nil }.count }
            guard count > 0 else { return nil }
            return played > 0
                ? "\(Format.duration(played)) over \(plural(count, "session", "sessions") ?? "")"
                : plural(count, "session", "sessions")
        case .beaten:
            return plural((game.completionEvents ?? []).filter { $0.deletedAt == nil }.count,
                          "time", "times")
        case .runs:
            return nil   // the section only exists when there is a template
        case .tracker:
            return game.trackerSchema == nil ? nil : "Set up"
        case .videos:
            return plural((game.videos ?? []).filter { $0.deletedAt == nil }.count,
                          "video", "videos")
        case .about:
            let summary = game.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return summary.isEmpty ? nil : "From IGDB"
        case .media:
            return plural(game.liveImages.count, "picture", "pictures")
        case .info:
            // Always has something to say — a platform, a release year, a
            // studio — so it is never "empty", just closed.
            return "Release, studio, genres"
        case .connections:
            // Not counted. The matching lives in `RelatedGamesSection` and
            // duplicating it here to produce a number would run it twice on
            // every game page. Naming what is inside is enough.
            return "Series and similar games"
        case .tags:
            return plural(game.userTags.count, "tag", "tags")
        case .review:
            guard let r = game.rating, r > 0 else { return nil }
            return "\(r) of 5"
        case .notes:
            let n = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "Written"
        }
    }

    /// One game-page section, collapse state scoped to this game — the
    /// title-only key collapsed a section on every game at once.
    @ViewBuilder
    private func sectionView(_ section: GamePageSection, stageMode: Bool) -> some View {
        switch section {
        case .sessions:
            CollapsibleSection("Sessions", icon: "stopwatch",
                               caption: caption(for: .sessions), isExpanded: expansion(.sessions)) {
                SessionControlsView(game: game)
            }
        case .beaten:
            CollapsibleSection("Beaten", icon: "flag.checkered",
                               caption: caption(for: .beaten), isExpanded: expansion(.beaten)) {
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
                CollapsibleSection("Runs", icon: "arrow.2.squarepath",
                                   caption: caption(for: .runs), isExpanded: expansion(.runs)) {
                    RunSectionView(game: game, template: template)
                }
            }
        case .tracker:
            // Open even when empty: the empty state here is "Set up a
            // tracker", a control rather than an absence.
            CollapsibleSection("Tracker", icon: "checklist",
                               caption: caption(for: .tracker), isExpanded: expansion(.tracker)) {
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
                               caption: caption(for: .videos), isExpanded: expansion(.videos)) {
                VideoListView(game: game, playing: $pagePlaying)
            }
        case .about:
            // **Yours opens; IGDB's stays closed.** See `sectionOpensByDefault`.
            CollapsibleSection("About", icon: "text.alignleft",
                               caption: caption(for: .about), isExpanded: expansion(.about)) {
                Text(game.summary ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .media:
            CollapsibleSection("Media", icon: "photo.stack",
                               caption: caption(for: .media), isExpanded: expansion(.media)) {
                ScreenshotStrip(game: game)
            }
        case .info:
            CollapsibleSection("Game Info", icon: "info.circle",
                               caption: caption(for: .info), isExpanded: expansion(.info)) {
                gameInfo
            }
            // Asked when the page appears, not when the section opens: the
            // answer takes a moment to arrive and a section that fills in
            // under your thumb is worse than one that was already right.
            //
            // Keyed on the slug so Fix Match re-pointing the game asks again
            // about the game it now IS. A game with no slug — added by hand —
            // is never asked about at all, because the only honest question
            // would be by name, and matching by name is how the wrong game's
            // logo got attached to one of these once already.
            .task(id: game.igdbSlug) {
                guard let slug = game.igdbSlug, !slug.isEmpty else {
                    wikidata = nil
                    return
                }
                let found = await WikidataService.cachedLookup(slug: slug)
                wikidata = found
                // Remember the entity, so a later feature does not have to
                // ask again to find out this game has one. Written only when
                // it changes — an identical value is not an edit.
                if let qid = found?.qid, game.wikidataID != qid {
                    repo.edit(game) { $0.wikidataID = qid }
                }
            }
        case .connections:
            CollapsibleSection("Connections", icon: "point.3.connected.trianglepath.dotted",
                               caption: caption(for: .connections), isExpanded: expansion(.connections)) {
                RelatedGamesSection(game: game)
            }
        case .tags:
            CollapsibleSection("Tags", icon: "tag",
                               caption: caption(for: .tags), isExpanded: expansion(.tags)) {
                tagsEditor
            }
        case .review:
            CollapsibleSection("Review", icon: "star.bubble",
                               caption: caption(for: .review), isExpanded: expansion(.review)) {
                reviewEditor
            }
        case .notes:
            // Open even when empty, like Tracker: an empty Notes is a
            // field waiting for you, not a section with nothing in it.
            CollapsibleSection("Notes", icon: "note.text",
                               caption: caption(for: .notes), isExpanded: expansion(.notes)) {
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
            // Classic's name sits at the very top beside the cover, so it
            // leaves the screen far sooner than showcase's, which is below a
            // cover and a panel. One threshold for both would hand over while
            // the name was still on screen in one of them.
            let threshold: CGFloat = switch layout {
            case .showcase: Self.heroTopSpace + Self.coverHeight + Self.titleBand
            // Classic's name is at the very top beside the cover and leaves
            // almost immediately; cover-led's sits UNDER a 190pt cover, so it
            // survives far longer than either.
            case .classic:  96
            case .coverLed: 8 + 190 * 4 / 3 + 40
            // Compact's name is the first thing on the page and the smallest
            // of the five, so it clears almost immediately.
            case .compact:  56
            }
            let handedOver = offset > threshold
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
        // The title handoff above already branches on Reduce Motion; this
        // full-pane horizontal slide is a much larger movement and did not.
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85),
                   value: stage)
        // Clips HORIZONTALLY only. The panes slide in and out sideways and
        // must not leak past the trailing edge — but the header art
        // deliberately draws ABOVE this container, pulled up by the safe-area
        // inset so it reaches under the navigation bar. A plain `.clipped()`
        // cut off exactly that overhang, so on iPad in landscape with a
        // compact tracker — the only combination that uses this layout — the
        // backdrop started below the bars with a band of empty page above it,
        // while the same page in portrait was fine.
        .mask(Rectangle().padding(.vertical, -4_000))
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
                        .background(LSTheme.cardFill, in: .circle)
                }
                .buttonStyle(.plain)
                .lsTapTarget()
                .accessibilityLabel("Close")
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
                    .background(LSTheme.cardFill, in: .circle)
            }
            .buttonStyle(.plain)
            .lsTapTarget()
            .accessibilityLabel(active.state == .running ? "Pause session" : "Resume session")
            Button {
                repo.stopSession(active)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(LSTheme.cardFill, in: .circle)
            }
            .buttonStyle(.plain)
            .lsTapTarget()
            .accessibilityLabel("Stop session")
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
                        .background(LSTheme.cardFill, in: .circle)
                }
                .buttonStyle(.plain)
                .lsTapTarget()
                .accessibilityLabel("Close")
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

    private var maskStops: [Gradient.Stop] {
        switch layout {
        case .showcase:
            [.init(color: .black, location: 0),
             .init(color: .black, location: 0.42),
             .init(color: .black.opacity(0.55), location: 0.62),
             .init(color: .clear, location: 0.92)]
        case .compact:
            // Almost nothing. A tint at the very top so the page isn't flat,
            // gone before the cover starts — the height an art band would
            // take is the whole point of this layout.
            [.init(color: .black.opacity(0.55), location: 0),
             .init(color: .black.opacity(0.18), location: 0.10),
             .init(color: .clear, location: 0.26)]
        case .classic, .coverLed:
            [.init(color: .black, location: 0),
             .init(color: .black.opacity(0.75), location: 0.18),
             .init(color: .black.opacity(0.22), location: 0.45),
             .init(color: .clear, location: 0.7)]
        }
    }

        /// The wordmark to draw, if any: the user's choice, else whatever was
    /// found automatically, else nothing and the name renders as text.
    ///
    /// Mirrors `backdropArtwork` deliberately — an explicit per-game pick
    /// beats a fetched one, and a fetched one beats going without.
    private var resolvedLogo: ResolvedArtwork {
        let chosen = game.resolvedArtwork(.logo)
        if !chosen.isEmpty { return chosen }
        if let fetchedLogo { return .remote(fetchedLogo) }
        return .none
    }

    /// Logos are off, the type is huge, or nothing was found — all three mean
    /// the same thing to the header: draw the name.
    private var headerLogo: ResolvedArtwork {
        guard ThemePalette.showGameLogos, !typeSize.isAccessibilitySize else { return .none }
        return resolvedLogo
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
                // The falloff belongs to the LAYOUT, not to taste.
                //
                // Showcase puts every word on a material panel, so nothing has
                // to be read off the art and it can hold full strength through
                // the band you actually see it in.
                //
                // Classic sets the name, status and stars directly on the
                // backdrop. There the art has to get out of the way by the
                // time the text starts, which is the brutal 22%-by-45% curve
                // the showcase header was built to escape. Serving both from
                // one gradient would mean picking which layout renders badly.
                .mask(
                    LinearGradient(stops: maskStops, startPoint: .top, endPoint: .bottom)
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
    /// in the art, and the game's name runs underneath them both, centered and
    /// large. An earlier pass had the name beside the cover on a full-width
    /// card it half-overlapped, which gave the title only the column left over
    /// after a 132pt cover — so a wordmark that is the most recognizable thing
    /// about a game got the smallest space on the page. Below, it gets the
    /// whole width.
    private var layout: GamePageLayout { ThemePalette.gamePageLayout }

    private var hero: some View {
        Group {
            switch layout {
            case .showcase: showcaseHero
            case .classic:  classicHero
            case .coverLed: coverLedHero
            case .compact:  compactHero
            }
        }
    }

    /// Build 32's header: the art leads, and everything that has to be read
    /// sits on a panel in front of it.
    private var showcaseHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: Self.heroTopSpace)

            if stacksCover {
                VStack(alignment: .leading, spacing: 12) {
                    coverThumb(width: Self.coverWidth)
                    factsPanel(fills: true)
                }
            } else {
                // Two spacers, so the pair is CENTERED rather than left-flush.
                // The panel takes the width its words need; without that it
                // stretched to the page margin and carried a stripe of empty
                // haze past the end of its own longest line. Hugging on the
                // right alone then left the pair ending short while the title
                // beneath it was centered — two alignments at once.
                //
                // Both spacers collapse when space is tight, so a long
                // platform name still gets the room.
                HStack(alignment: .top, spacing: 10) {
                    Spacer(minLength: 0)
                    coverThumb(width: Self.coverWidth)
                    factsPanel(fills: false)
                        .padding(.top, 26)
                        // Spacers are greedy and text is compressible, so
                        // without this the two of them split the row with the
                        // panel and wrapped "Now Playing" onto a second line.
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
            }

            heroTitle

            OwnershipControl(ownership: $game.ownership, centered: true)

            if showGameStats {
                GameStatsRow(game: game, showsRuns: repo.runTrackingEnabled(for: game))
            }
        }
    }

    /// What the app had before build 32, kept as a choice rather than a
    /// fallback. Cover on the left, the facts beside it, the name as text.
    ///
    /// The words sit directly on the backdrop here — there is no panel — which
    /// is exactly why `coverBackdrop` fades the art much harder in this
    /// layout. That is not a lesser backdrop, it is the one this arrangement
    /// requires; the showcase header can afford a bold image precisely because
    /// nothing has to be read off it.
    private var classicHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            classicLayout {
                coverThumb(width: 138)

                VStack(alignment: .leading, spacing: 8) {
                    // Honors the same "Use game logos" switch as showcase, at
                    // the size this column can actually carry. A wordmark
                    // needs width to read and there isn't much beside a 138pt
                    // cover, so it gets a modest band rather than the full
                    // one — and anyone who finds that busy has a switch.
                    if !headerLogo.isEmpty {
                        ArtworkView(headerLogo, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 54, alignment: .leading)
                            .accessibilityLabel(game.name)
                    } else {
                        Text(game.name)
                            .font(.title2.bold())
                    }
                    heroFacts
                }
                Spacer(minLength: 0)
            }

            OwnershipControl(ownership: $game.ownership)

            if showGameStats {
                GameStatsRow(game: game, showsRuns: repo.runTrackingEnabled(for: game))
            }
        }
    }

    /// For a library read at speed. No art band, a small cover, the facts
    /// beside it, and the sections beginning almost at once.
    ///
    /// This is the one layout where the backdrop is deliberately almost gone
    /// even when the library preference asks for cover art — a tall band of
    /// image is exactly the thing being traded away for reaching the tracker
    /// without scrolling. See `maskStops`.
    private var compactHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            classicLayout {
                coverThumb(width: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    heroFacts
                }
                Spacer(minLength: 0)
            }

            OwnershipControl(ownership: $game.ownership)

            if showGameStats {
                GameStatsRow(game: game, showsRuns: repo.runTrackingEnabled(for: game))
            }
        }
        .padding(.top, 4)
    }

    /// The box on a shelf. One large cover, centered, and everything else
    /// beneath it — the arrangement a physical game has when you pick it up.
    ///
    /// Nothing sits beside the cover, which is what lets it be this big: at
    /// 190pt there is no column left for facts, and trying to keep one is how
    /// the other two layouts ended up capping their covers at 132 and 138.
    private var coverLedHero: some View {
        VStack(spacing: 12) {
            Color.clear.frame(height: 8)

            coverThumb(width: min(190, Self.coverWidth * 1.45))

            if !headerLogo.isEmpty {
                ArtworkView(headerLogo, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 78)
                    .accessibilityLabel(game.name)
            } else {
                Text(game.name)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
            }

            heroFacts(alignment: .center)
                .frame(maxWidth: .infinity)

            OwnershipControl(ownership: $game.ownership, centered: true)

            if showGameStats {
                GameStatsRow(game: game, showsRuns: repo.runTrackingEnabled(for: game))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// At accessibility text sizes a fixed cover and five stars cannot share a
    /// line, and one over-wide child drags the whole page's column offscreen.
    private var classicLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    /// What this game is to you: where it sits, what you scored it, what the
    /// critics said. Shared by both layouts — showcase puts it on a panel,
    /// classic sets it directly beside the cover.
    var heroFacts: some View { heroFacts(alignment: .leading) }

    func heroFacts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            // Two facts, and at accessibility sizes they are two lines.
            // Wrapping them inside one row hyphenated "Now Play-ing" and
            // pushed the platform past the edge; the separator dot also stops
            // making sense once the pair is stacked.
            // **Side by side if it fits, stacked if it doesn't — never cut.**
            //
            // This used to be one line with `lineLimit(1)`, and on Hollow
            // Knight at default size it rendered "Now Playi… · Switch". Tim,
            // looking at that: *"the … takes up basically as much space as
            // 'ng' would."* Which is the whole case against truncating here —
            // it bought no width, it only cost the word. Scaling harder has
            // the same problem in a quieter way: the row gets smaller than
            // everything around it to save a couple of points.
            //
            // So the give is a line break, not a smaller word and not an
            // ellipsis. `ViewThatFits` proposes the horizontal pair first and
            // falls back to the stack, which is the layout accessibility sizes
            // already use — one rule, reached two ways.
            //
            // Both children stay `lineLimit(1)`, which is what keeps the old
            // fix intact: a wrapping Text answers a narrow proposal by growing
            // taller instead of asking for room, and that is how "Now Playing"
            // once ended up on two lines inside a panel with space to spare.
            // Neither of these wraps, so the panel's ideal width is still the
            // honest one-line width that `layoutPriority` acts on.
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: 6) {
                        statusPair
                        if game.primaryOwnedPlatform != nil {
                            Text("·").foregroundStyle(.tertiary)
                            platformPair
                        }
                    }
                }
                VStack(alignment: alignment, spacing: 4) {
                    statusPair
                    if game.primaryOwnedPlatform != nil { platformPair }
                }
            }
            .font(.subheadline)
            // This line sets the panel's width, so it must not be willing to
            // wrap: a wrapping Text answers a narrow proposal by growing
            // taller instead of asking for more room, so the panel settled
            // small and the centering spacers pocketed the difference — which
            // is how "Now Playing" ended up on two lines inside a panel with
            // space to spare. One line makes its ideal width honest, which is
            // what `layoutPriority` on the panel then acts on.
            //
            // NOT `fixedSize`: that makes the width a demand rather than a
            // preference, and the panel pushed the whole page column wider
            // than the screen — every section divider below ran off the right
            // edge. Scaling is the give of last resort, for the rare platform
            // `PlatformShort` has no abbreviation for.
            // …but only below accessibility sizes. All of the above is about
            // the panel proposing an honest width; at AX sizes the same rule
            // rendered the status as "Now…" instead of "Now Playing", and a
            // panel measured correctly around a truncated word is the wrong
            // trade. Wrapping is what accessibility sizes are for.
            // The comment above was already the intent; the code was not.
            // Applied unconditionally, this one-line limit reached the PLATFORM
            // too, so at AX XXXL the stack that had just been fixed to keep
            // "Now Playing" whole showed "Sega Mega Dri…" underneath it. Codex
            // verified it on the simulator, 2026-09-07.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            // The glyphs repeat what the words already say, and were being
            // announced as separate elements ahead of them.
            .accessibilityElement(children: .combine)

            RatingControl(rating: $game.rating)

            // Directly under your own verdict, because the comparison is the
            // entire point — a critic score parked elsewhere on the page is
            // just trivia.
            //
            // On the panel's ordinary 8-point rhythm, deliberately. Squeezing
            // this pair together was the first, wrong answer to the label
            // floating mid-panel: it glued the label to the score instead of
            // to its stars. The space that needed removing was inside
            // `RatingControl`, under the stars themselves.
            referenceRow

            if let franchise = game.franchise, !franchise.isEmpty {
                Text(franchise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The showcase header's panel: `heroFacts` on translucent material, which
    /// is what lets the art behind it stay at full strength.
    ///
    /// `fills` is true only where the panel is alone on its row (accessibility
    /// sizes), where hugging its content would leave it stranded mid-page.
    private func factsPanel(fills: Bool) -> some View {
        heroFacts
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LSTheme.hairline, lineWidth: 1)
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
    /// **A borrowed logo never stands alone.**
    ///
    /// `LogoArt` looks a logo up BY NAME, which is the only way a manually
    /// added game gets any art at all — and also how a typo shows somebody
    /// else's logo with your own title nowhere on the screen. A "Legend of
    /// Heroes: Trails of Cold Steel IV" typed by hand came back wearing the
    /// Japanese logo for a different game, and the name it was actually filed
    /// under appeared nowhere above the fold.
    ///
    /// Tim, asked whether to keep fetching by name: *"yours"* — which was
    /// fetch it, but never without the typed name visible. So a game the app
    /// never matched to IGDB shows the logo AND the name under it. A matched
    /// game is unchanged: its logo is its own.
    private var logoIsBorrowed: Bool {
        game.igdbID == nil && fetchedLogo != nil && game.resolvedArtwork(.logo).isEmpty
    }

    /// Whether the hero is actually drawing artwork behind its title.
    ///
    /// A5. The title's own comment has said "white text" for builds, and its
    /// shadow was tuned for white — but nothing ever SET white, so it
    /// inherited `.primary` and rendered near-black over the art in the light
    /// appearance. Tim left the call to me; the answer is white, because the
    /// title sits on a photograph rather than on the page.
    ///
    /// It is conditional rather than unconditional for the case that answer
    /// skips over: the backdrop can be turned off, and the page background can
    /// be a plain, accent or status ground instead of the cover. Then the
    /// title is on the THEME, not on art, and forcing white would be white on
    /// a light ground — invisible, which is a worse bug than the one being
    /// fixed. Over the theme it goes back to theme ink.
    private var heroSitsOnArtwork: Bool {
        switch ThemePalette.pageBackground {
        case .cover, .keyArt, .screenshot:
            return ThemePalette.backdropIntensity != .off && !backdropArtwork.isEmpty
        case .plain, .accent, .status:
            return false
        }
    }

    /// The status glyph and its word, as one unbreakable unit.
    private var statusPair: some View {
        HStack(spacing: 6) {
            Image(systemName: game.status.systemImage)
                .foregroundStyle(game.status.color)
            Text(game.status.label)
        }
    }

    /// The console icon and its short name, likewise. `PlatformShort` already
    /// shortens these, but "Sega Mega Drive/Genesis" is still a mouthful next
    /// to a status — which is the case the stack exists for.
    @ViewBuilder
    private var platformPair: some View {
        if let platform = game.primaryOwnedPlatform {
            HStack(spacing: 6) {
                PlatformIconView(platform: platform, size: 20)
                Text(PlatformShort.name(platform)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var heroTitle: some View {
        let artwork = headerLogo
        if !artwork.isEmpty {
            VStack(spacing: 6) {
                ArtworkView(artwork, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.titleBand)
                    .accessibilityLabel(game.name)
                if logoIsBorrowed {
                    Text(game.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        // On the art, so it takes the same ink as the title
                        // below. See `heroSitsOnArtwork`.
                        .foregroundStyle(heroSitsOnArtwork ? AnyShapeStyle(.white)
                                                           : AnyShapeStyle(.primary))
                        .shadow(color: .black.opacity(heroSitsOnArtwork ? 0.55 : 0),
                                radius: 8, y: 2)
                        // The logo already said a name; this one is the name
                        // that is actually stored, so the pair is not read out
                        // twice.
                        .accessibilityHidden(true)
                }
            }
        } else {
            Text(game.name)
                // `.largeTitle` at AX XXXL is around 55pt, and "Hollow Knight"
                // does not fit a phone at that size however it wraps — it ran
                // off the right edge. `.title` still scales with Dynamic Type,
                // so this is not a cap; it is a smaller starting point for the
                // one piece of type on the page that is large for effect
                // rather than for reading. The name is also in the navigation
                // bar and read first by VoiceOver, so nothing is lost.
                .font((typeSize.isAccessibilitySize ? Font.title : .largeTitle).bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // Infinite width with no instruction to grow taller instead:
                // at AX XXXL "Hollow Knight" ran off the right edge. This is
                // the app's own accessibility pattern, used here for the first
                // time on the hero.
                .fixedSize(horizontal: false, vertical: true)
                // Unlike the panel's copy, this sits directly on the art —
                // so it is white there, not theme ink (A5). It survives on a
                // photograph because it's large and heavy, but a bright
                // screenshot can still swallow white text, so it carries its
                // own shadow rather than trusting the backdrop to be dark.
                //
                // With no art behind it there is nothing to knock out of and
                // nothing to hide from: theme ink, and no shadow to smear it
                // against the page's own ground.
                .foregroundStyle(heroSitsOnArtwork ? AnyShapeStyle(.white)
                                                   : AnyShapeStyle(.primary))
                .shadow(color: .black.opacity(heroSitsOnArtwork ? 0.55 : 0),
                        radius: 8, y: 2)
        }
    }

    private func coverThumb(width: CGFloat) -> some View {
        CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
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
    /// What Wikidata says about this game, once asked. Nil until it answers,
    /// and nil forever if it has nothing — see `creditsBlock`.
    @State private var wikidata: WikidataService.Entry?
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

    /// **Who made it, which IGDB cannot say.**
    ///
    /// Asked for every field it populates, IGDB has no person or credit field
    /// at all — every credit is company-level through `involved_companies`.
    /// So the studio row above comes from IGDB and the names here come from
    /// Wikidata, and the section says which is which rather than presenting
    /// one library with two silent sources.
    ///
    /// **It appears or it does not.** No spinner, no "couldn't load", no empty
    /// state: this is enrichment on a page that is complete without it, and a
    /// failed lookup that announces itself would put an error on a game page
    /// every time somebody opened one on a train.
    @ViewBuilder
    private var creditsBlock: some View {
        if let entry = wikidata, !entry.orderedCredits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("Credits")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    ForEach(entry.orderedCredits) { credit in
                        GridRow {
                            Text(credit.label)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .gridColumnAlignment(.leading)
                            Text(credit.name)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // **A disagreement is a question, never a correction.** The
                // app does not quietly substitute one source for another —
                // the same rule the local cover override follows.
                if let clash = WikidataService.releaseYearDisagreement(
                    entry, storedFirstRelease: game.firstReleaseDate) {
                    Label("Wikidata says \(String(clash.wikidata)); this says \(String(clash.stored)).",
                          systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(LSTheme.working)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Credits from Wikidata.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Credits from Wikidata. "
                + entry.orderedCredits.map { "\($0.label), \($0.name)" }
                    .joined(separator: ". "))
        }
    }

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
                        // UTC, because a release date is a calendar date. A
                        // year-only 2026 is stored at UTC midnight on 1
                        // January, and the local calendar reads that as 2025
                        // anywhere west of Greenwich.
                        infoCell("Released", game.firstReleaseDate.map {
                            String(ReleaseCountdown.utc.component(.year, from: $0))
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
                creditsBlock
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
                            String(ReleaseCountdown.utc.component(.year, from: $0))
                        } ?? ""
                    },
                    set: { text in
                        if let year = Int(text), (1950..<3000).contains(year) {
                            // UTC, matching the getter above and every other
                            // release fact: a local-midnight 1 January is the
                            // previous year east of UTC.
                            game.firstReleaseDate = DateComponents(
                                calendar: ReleaseCountdown.utc, year: year, month: 1, day: 1).date
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
            // MORE than one, not merely non-empty.
            //
            // A one-entry list is almost never IGDB's answer — it is the
            // platform picked when the game was added, before any refresh
            // merged the rest in. Celeste sat at ["Mac"] with a full IGDB
            // record behind it, and treating that as authoritative hid the
            // catalog behind a submenu on exactly the game that needed it
            // most. Two or more means a merge has happened.
            PlatformEditor(platforms: $game.platforms,
                           owned: Binding(
                            get: { game.ownedPlatformNames },
                            set: { game.ownedPlatforms = $0 }),
                           listIsAuthoritative: game.igdbID != nil && game.platforms.count > 1)
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

    /// A labeled value, tappable when there's a slice of the library behind
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
        // Ownership you actually declared. `ownedPlatformNames` falls back to
        // the first platform IGDB lists when you own none — fine for choosing
        // an icon, and a lie on a badge that says MINE. Onimusha showed
        // "Nintendo Switch 2 · MINE" for a wishlist game nobody had claimed.
        let mine = Set(game.ownedPlatforms ?? [])
        return VStack(alignment: .leading, spacing: 6) {
            Text("Platforms").font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(PlatformShort.ownedFirst(game.platforms,
                                                 owned: game.ownedPlatformNames), id: \.self) { platform in
                    if mine.contains(platform) {
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
                        // Gray, not blue. Accent means "mine" on the row above;
                        // a second saturated color beside it read as a second
                        // kind of selected, and stayed blue whatever the app's
                        // accent was. Codex K5, the editor's other half.
                        Chip(text: platform, tint: .secondary)
                    }
                }
            }

            // Schema V4's whole point. A game can be out on one machine and
            // months away on another, and until the dates were stored per
            // platform the app could only ever say one of those things.
            let upcoming = game.upcomingReleases()
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(upcoming, id: \.platform) { release in
                        HStack(spacing: 6) {
                            PlatformIconView(platform: release.platform, size: 13)
                            Text(PlatformShort.name(release.platform))
                            Text(ReleaseCountdown.dateLabel(release.date))
                                .foregroundStyle(.secondary)
                            if let soon = ReleaseCountdown.countdown(to: release.date) {
                                Text("· \(soon)").foregroundStyle(LSTheme.accent)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 2)
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
    /// Whether the whole bundled vocabulary is on screen, rather than the
    /// first handful. Off by default: forty chips under a text field is a
    /// catalogue, and this is meant to be a shortcut.
    @State private var showingAllSuggestedTags = false

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
            suggestedVocabulary
        }
    }

    /// **The bundled vocabulary — Stage 2.**
    ///
    /// An empty text field is the moment this exists for: IGDB has already
    /// told you Hollow Knight is "Platform / Adventure / Indie", and the word
    /// you actually want is Metroidvania. Nothing here is applied for you —
    /// tapping one adds an ordinary tag, and free text still works exactly as
    /// it did.
    @ViewBuilder
    private var suggestedVocabulary: some View {
        let offered = suggestedTagNames
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(newTag.isEmpty ? "Suggested" : "From the vocabulary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Only when there is more to see, and only when the field
                    // is empty — while typing, the list is already a filter.
                    if newTag.isEmpty, suggestedPool.count > Self.suggestedTagPreview {
                        Button(showingAllSuggestedTags ? "Fewer" : "All \(suggestedPool.count)") {
                            withAnimation(.snappy(duration: 0.2)) {
                                showingAllSuggestedTags.toggle()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(LSTheme.accent)
                        .lsTapTargetTall()
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(offered, id: \.self) { name in
                        Button { addTag(name) } label: {
                            Chip(text: "+ \(name)", tint: .gray)
                        }
                        .buttonStyle(.plain)
                        .lsTapTargetTall()
                        .accessibilityLabel("Add tag \(name)")
                    }
                }
            }
        }
    }

    /// How many of the vocabulary to show before asking.
    private static let suggestedTagPreview = 8

    /// Everything the vocabulary could offer this game: not already on it, and
    /// not already offered by the library's own words just above.
    private var suggestedPool: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        let source = typed.isEmpty ? SuggestedTags.all : SuggestedTags.matching(typed)
        let alreadyShown = Set(tagSuggestions.map { $0.lowercased() })
        let onGame = Set(game.userTags.map { $0.lowercased() })
        return source.map(\.name).filter {
            !onGame.contains($0.lowercased()) && !alreadyShown.contains($0.lowercased())
        }
    }

    private var suggestedTagNames: [String] {
        newTag.isEmpty && !showingAllSuggestedTags
            ? Array(suggestedPool.prefix(Self.suggestedTagPreview))
            : suggestedPool
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
