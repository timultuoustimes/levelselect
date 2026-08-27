import SwiftUI
import SwiftData

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var fixingMatch = false
    @State private var arrangingSections = false
    @State private var pickingCover = false
    /// Library-wide reading preference, device-local like the Stats cards.
    @AppStorage("gameSectionOrder") private var sectionOrderRaw = ""
    @AppStorage("gameHiddenSections") private var hiddenSectionsRaw = ""
    @State private var browserTarget: DekuLinkTarget?
    @State private var markingBeaten = false
    @State private var editingOutcomeNote = false
    @State private var outcomeNoteDraft = ""

    @State private var pagePlaying: GameVideo?
    @State private var showingCover = false
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
        .ignoresSafeArea(.container, edges: .bottom)
        .background { ambientBackdrop }
        .overlay {
            if showingCover {
                CoverShowcase(urlString: game.displayCoverURLString, isPresented: $showingCover)
            }
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
        .navigationTitle(game.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        repo.edit(game) { $0.pinned.toggle() }
                    } label: {
                        Label(game.pinned ? "Unpin" : "Pin", systemImage: game.pinned ? "pin.slash" : "pin")
                    }
                    Menu("Status") {
                        ForEach(GameStatus.allCases, id: \.self) { s in
                            Button {
                                repo.edit(game) { $0.status = s }
                            } label: {
                                Label(s.label, systemImage: game.status == s ? "checkmark" : s.systemImage)
                            }
                        }
                    }
                    Button {
                        markingBeaten = true
                    } label: {
                        Label("Mark as Beaten…", systemImage: "flag.checkered")
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
                    Menu("Item Hints") {
                        Button {
                            repo.edit(game) { $0.showItemHintsOverride = nil }
                        } label: {
                            Label("Follow Default", systemImage:
                                    game.showItemHintsOverride == nil ? "checkmark" : "gear")
                        }
                        Button {
                            repo.edit(game) { $0.showItemHintsOverride = true }
                        } label: {
                            Label("Show Hints", systemImage:
                                    game.showItemHintsOverride == true ? "checkmark" : "eye")
                        }
                        Button {
                            repo.edit(game) { $0.showItemHintsOverride = false }
                        } label: {
                            Label("Hide Hints (play blind)", systemImage:
                                    game.showItemHintsOverride == false ? "checkmark" : "eye.slash")
                        }
                    }
                    Menu("Tracker Display") {
                        Button {
                            repo.edit(game) { $0.trackerDisplayRaw = nil }
                        } label: {
                            Label("Follow Default (\(ThemePalette.defaultTrackerDisplay.label))",
                                  systemImage: game.trackerDisplayRaw == nil ? "checkmark" : "circle.dashed")
                        }
                        ForEach(TrackerDisplay.allCases, id: \.rawValue) { choice in
                            Button {
                                repo.edit(game) { $0.trackerDisplayRaw = choice.rawValue }
                            } label: {
                                Label(choice.label, systemImage:
                                      game.trackerDisplayRaw == choice.rawValue ? "checkmark" : "circle")
                            }
                        }
                    }
                    Divider()
                    Button {
                        arrangingSections = true
                    } label: {
                        Label("Arrange Sections…", systemImage: "arrow.up.arrow.down")
                    }
                    Button {
                        pickingCover = true
                    } label: {
                        Label("Change Cover…", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        fixingMatch = true
                    } label: {
                        Label("Fix Match…", systemImage: "link.badge.plus")
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
        .sheet(isPresented: $fixingMatch) {
            FixMatchView(game: game)
        }
        .sheet(isPresented: $arrangingSections) {
            GameArrangeSheet(orderRaw: $sectionOrderRaw, hiddenRaw: $hiddenSectionsRaw)
        }
        .sheet(isPresented: $pickingCover) {
            CoverPickerView(game: game)
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
        // Same overflow rule as the hero: capsule plus caption can outgrow
        // the screen at accessibility sizes, so they stack instead.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        let activeFinished = game.activePlaythrough?.isFinished == true
        return layout {
            Menu {
                // A finished run shouldn't be the path of least resistance:
                // when the current one is done, starting fresh leads.
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
                Menu("How it ended") {
                    Button {
                        if let pt = game.activePlaythrough {
                            repo.setPlaythroughOutcome(pt, outcome: nil, note: nil)
                        }
                    } label: {
                        Label("Still going", systemImage: game.activePlaythrough?.outcome == nil
                              ? "checkmark" : "play.circle")
                    }
                    ForEach(PlaythroughOutcome.allCases, id: \.self) { choice in
                        Button {
                            if let pt = game.activePlaythrough {
                                repo.setPlaythroughOutcome(pt, outcome: choice, note: pt.outcomeNote)
                                outcomeNoteDraft = pt.outcomeNote ?? ""
                                editingOutcomeNote = true
                            }
                        } label: {
                            Label(choice.label,
                                  systemImage: game.activePlaythrough?.outcome == choice
                                  ? "checkmark" : choice.systemImage)
                        }
                    }
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

    private func standardScroll(stageMode: Bool) -> some View {
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
            case .cover:
                coverBackdrop
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var coverBackdrop: some View {
        if let s = game.displayCoverURLString, let url = URL(string: s) {
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

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            // At accessibility text sizes the cover-beside-text row can't fit
            // its own minimums (fixed cover + five stars beat the screen), and
            // one over-wide child drags the whole page's column offscreen with
            // it. Stack instead: cover above, text at full width.
            heroLayout {
                CoverThumb(urlString: game.displayCoverURLString)
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
                        if let platform = PlatformPreference.owned(game.platforms) {
                            Text("·").foregroundStyle(.tertiary)
                            PlatformIconView(platform: platform, size: 20)
                            Text(PlatformShort.name(platform)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    RatingControl(rating: $game.rating)

                    // Directly under your own verdict, because the comparison
                    // is the entire point — a critic score parked elsewhere on
                    // the page is just trivia.
                    referenceRow

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

    private var heroLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

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
