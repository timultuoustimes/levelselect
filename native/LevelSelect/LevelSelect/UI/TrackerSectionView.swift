import SwiftUI
import SwiftData

/// Objective tracker: schema-driven checklist (categories → items) with
/// per-playthrough state. Personal Goals are user-added items in the same
/// schema. Everything syncs via CloudKit like the rest of the model.
struct TrackerSectionView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @State private var hideCompleted = false
    /// Per game, and remembered: "I'm only working on Shrines right now" is a
    /// statement about this game, and it outlives one visit to the screen.
    @AppStorage private var hidePlanned: Bool
    @State private var addingGoal = false
    @State private var goalName = ""
    @State private var expanded: Set<String> = []
    /// Generation state lives in a shared store, not here — a view's `@State`
    /// dies when you navigate away, and generation takes a minute or two.
    @State private var generation = TrackerGenerationStore.shared
    @State private var confirmingRegenerate = false
    @State private var importingList = false
    /// Rename target: category id, plus an item id when renaming an item.
    @State private var renaming: (category: String, item: String?)?
    @State private var renameText = ""
    @State private var editing: EditTarget?
    /// A tick that would close other things off, held until confirmed.
    @State private var confirmingLockout: LockoutPrompt?
    @State private var planningCategory = false
    @State private var plannedName = ""
    @State private var plannedCount = ""
    @State private var builtinAvailable = false
    @State private var confirmingUseBuiltin = false
    /// Both removals share one confirmation. Four confirmation dialogs already
    /// hang off this view and presentation here is a single-occupancy slot —
    /// one binding with a payload, not two more modifiers.
    @State private var removing: RemovalTarget?

    /// What a pending removal would destroy, resolved before the dialog opens
    /// so it can say the number rather than warn vaguely.
    struct RemovalTarget: Identifiable {
        /// nil = the whole tracker.
        let categoryID: String?
        let name: String
        let cost: Repository.RemovalCost
        var id: String { categoryID ?? "__tracker__" }
    }

    init(game: Game) {
        self.game = game
        _hidePlanned = AppStorage(wrappedValue: false, "hidePlanned.\(game.id.uuidString)")
    }

    /// An item whose completion ends other things, and what it ends.
    struct LockoutPrompt: Identifiable {
        let item: TrackerItemDTO
        let losing: [String]
        var id: String { item.id }
    }

    private var repo: Repository { Repository(context) }

    private var playthrough: Playthrough? {
        game.activePlaythrough
    }

    private var usingBuiltin: Bool {
        game.trackerSchema?.source == .builtIn
    }

    private var categories: [TrackerCategoryDTO] {
        // Through the repository, not the blob directly: a note or a rename
        // may live in a TrackerItemDetail record that the blob doesn't have
        // yet (or has a staler copy of). One read path means the tracker page,
        // the widget and the merge engine can't disagree about what an item
        // is called.
        repo.trackerCategories(for: game)
    }

    /// Built ONCE per render in `body` and threaded down as a parameter.
    ///
    /// As a computed property referenced from the header, every category and
    /// every row, it was rebuilt — a full scan of every state record — on each
    /// reference, making one render of a large tracker roughly
    /// O(items × states). At 180 items that's ~180 rebuilds of a 180-entry
    /// dictionary per frame. Same data, built once, passed down.
    private var stateByItem: [String: TrackerStateRecord] {
        Dictionary(
            (playthrough?.trackerStates ?? [])
                .filter { $0.deletedAt == nil }
                .map { ($0.itemID, $0) },
            // Same winner rule as the repository read — "whichever row the
            // relationship listed first" could show a different state than
            // repo.trackerState until reconciliation ran.
            uniquingKeysWith: { a, b in b.outranks(a) ? b : a }
        )
    }

    /// Built once per render beside the state map — gating is a whole-tracker
    /// question (an item elsewhere can close this one), so per-row scanning
    /// would be the same O(items²) mistake the state map already fixed.
    private func resolver(_ cats: [TrackerCategoryDTO],
                          states: [String: TrackerStateRecord]) -> TrackerGating.Resolver {
        TrackerGating.Resolver(
            categories: cats,
            completed: Set(states.filter { $0.value.completed }.keys))
    }

    var body: some View {
        let cats = categories
        let states = stateByItem
        let gating = resolver(cats, states: states)
        VStack(alignment: .leading, spacing: 12) {
            header(cats, states: states)

            if let started = generation.startDate(for: game.id) {
                GeneratingTrackerView(startedAt: started,
                                      kind: generation.kind(for: game.id)) {
                    generation.cancel(for: game.id)
                }
                .padding(.vertical, 2)
            } else if cats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No tracker yet. Generate the whole thing, or plan it out first and fill it in a piece at a time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // Offered here because "what should I even be tracking?" is
                    // the question people actually have on an empty tracker,
                    // and it is answerable in a few seconds rather than the two
                    // minutes a full generation costs.
                    Button {
                        generation.suggestCategories(for: game, context: context)
                    } label: {
                        Label("Suggest Categories", systemImage: "list.bullet.rectangle.portrait")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .tint(LSTheme.accent)
                }
            }

            // Existing content stays visible while regenerating — hiding it
            // made a regenerate look like the tracker had been wiped.
            let hiddenPlanned = hidePlanned ? cats.filter(\.pending).count : 0
            ForEach(hidePlanned ? cats.filter { !$0.pending } : cats) { category in
                categoryView(category, states: states, gating: gating)
            }
            // Never a silent disappearance: the count is the way back, and
            // without it a tracker you'd hidden half of just looks short.
            if hiddenPlanned > 0 {
                Button {
                    hidePlanned = false
                } label: {
                    Label("\(hiddenPlanned) planned categor\(hiddenPlanned == 1 ? "y" : "ies") hidden",
                          systemImage: "eye.slash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
            }

            if let outcome = generation.outcome(for: game.id), !outcome.isNoOp {
                mergeSummary(outcome)
            }

            if let error = generation.error(for: game.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(LSTheme.working)
                    Spacer(minLength: 4)
                    Button("Dismiss") { generation.clearError(for: game.id) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
                // The app-wide banner exists because a generation usually fails
                // while you're somewhere else entirely. If you were standing
                // right here watching it fail, you have already been told —
                // being told again on the next screen is nagging. This row only
                // renders when the message is genuinely on screen (the section
                // builds no content while collapsed), so it is a real "seen".
                .onAppear { dismissRedundantNotice() }
                .onChange(of: generation.notice?.id) { _, _ in dismissRedundantNotice() }
            }

            // Six flat buttons wrapped onto three lines and hyphenated words
            // mid-syllable ("Regen-erate", "Catego-ry"). Grouped into four
            // controls instead: the two anyone reaches for often, and two
            // menus for the rest.
            HStack(spacing: 18) {
                // The button says what it will do, and the menu lets you run it
                // differently just this once without changing the default —
                // "this tracker is terrible, replace the lot" shouldn't mean a
                // trip to Settings.
                Menu {
                    ForEach(TrackerGenerationAction.allCases) { choice in
                        Button {
                            start(choice)
                        } label: {
                            Label(choice.label, systemImage: choice.systemImage)
                        }
                    }
                } label: {
                    Label(defaultAction.buttonTitle(regenerating: hasNonGoalContent),
                          systemImage: "sparkles")
                        .font(.subheadline)
                } primaryAction: {
                    start(defaultAction)
                }
                .disabled(isGenerating)

                Menu {
                    Button {
                        generation.suggestCategories(for: game, context: context)
                    } label: {
                        Label("Suggest Categories", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .disabled(isGenerating)
                    Button {
                        plannedName = ""
                        plannedCount = ""
                        planningCategory = true
                    } label: { Label("Plan a Category", systemImage: "square.dashed") }
                    Divider()
                    Button {
                        goalName = ""
                        addingGoal = true
                    } label: { Label("Add Personal Goal", systemImage: "plus.circle") }
                    Button {
                        importingList = true
                    } label: { Label("Paste a List", systemImage: "doc.on.clipboard") }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                }

                // Pushed, not presented — this view already carries three
                // sheets, and sheets on this screen have swallowed each other
                // twice before.
                NavigationLink {
                    RetroAchievementsImportView(game: game)
                } label: {
                    Label("RetroAchievements", systemImage: "trophy")
                        .font(.subheadline)
                }

                Menu {
                    if builtinAvailable && !usingBuiltin {
                        Button {
                            confirmingUseBuiltin = true
                        } label: { Label("Use Built-in Tracker", systemImage: "checkmark.seal") }
                            .disabled(isGenerating)
                    }
                    if game.trackerSchema != nil {
                        Divider()
                        Button(role: .destructive) {
                            removing = RemovalTarget(categoryID: nil, name: game.name,
                                                     cost: repo.removalCost(for: game))
                        } label: { Label("Remove Tracker", systemImage: "trash") }
                            .disabled(isGenerating)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
        }
        .task(id: game.id) {
            builtinAvailable = BuiltinTrackers.match(for: game) != nil
        }
        .confirmationDialog(
            "Regenerate this tracker?",
            isPresented: $confirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) {
                generation.generate(for: game, context: context, action: .replace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the current tracker content. Personal Goals are kept, and progress follows any item that comes back under a new name — but anything the new tracker drops loses its progress.")
        }
        .confirmationDialog(
            removing.map { $0.categoryID == nil ? "Remove this tracker?" : "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { removing != nil },
                                 set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button(removing?.categoryID == nil ? "Remove Tracker" : "Delete Category",
                   role: .destructive) {
                if let target = removing {
                    if let id = target.categoryID {
                        repo.removeCategory(from: game, categoryID: id)
                    } else {
                        repo.removeTracker(from: game)
                    }
                }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text(removalWarning)
        }
        .sheet(isPresented: $importingList) {
            TrackerListImportView(game: game)
        }
        .sheet(item: $editing) { target in
            TrackerItemEditView(game: game, target: target)
        }
        .alert("Plan a Category", isPresented: $planningCategory) {
            TextField("Name (Bosses, Charms, Endings…)", text: $plannedName)
            TextField("About how many? (optional)", text: $plannedCount)
                #if !os(macOS)
                .keyboardType(.numberPad)
                #endif
            Button("Add") {
                repo.addPlannedCategory(to: game, named: plannedName,
                                        plannedCount: Int(plannedCount))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sketch the shape of the tracker first, then fill each part in one at a time — each one generates on its own without disturbing the rest.")
        }
        .confirmationDialog(
            "Tick “\(confirmingLockout?.item.name ?? "")”?",
            isPresented: Binding(get: { confirmingLockout != nil },
                                 set: { if !$0 { confirmingLockout = nil } }),
            titleVisibility: .visible
        ) {
            Button("Tick it") {
                if let prompt = confirmingLockout {
                    let pt = repo.ensureDefaultPlaythrough(for: game)
                    repo.setTrackerItem(pt, itemID: prompt.item.id, done: true)
                }
                confirmingLockout = nil
            }
            Button("Cancel", role: .cancel) { confirmingLockout = nil }
        } message: {
            Text("This closes off \(confirmingLockout?.losing.joined(separator: ", ") ?? "") for this playthrough. You can untick it if you change your mind.")
        }
        .sheet(isPresented: Binding(
            get: { generation.pendingMerge(for: game.id) != nil },
            set: { if !$0 { generation.discardPending(for: game.id) } }
        )) {
            if let merge = generation.pendingMerge(for: game.id) {
                TrackerMergeReviewView(game: game, merge: merge)
            }
        }
        .confirmationDialog(
            "Switch to the built-in tracker?",
            isPresented: $confirmingUseBuiltin,
            titleVisibility: .visible
        ) {
            Button("Use Built-in Tracker") { repo.useBuiltinSchema(for: game) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the current tracker with LevelSelect's curated tracker for this game. Personal Goals are kept, but checked items may not match.")
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                guard let target = renaming else { return }
                repo.renameTracker(game, categoryID: target.category,
                                   itemID: target.item, to: renameText)
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("A generator's naming is a suggestion. Renaming keeps your progress and won't confuse a future regeneration.")
        }
        .alert("New Personal Goal", isPresented: $addingGoal) {
            TextField("Goal", text: $goalName)
            Button("Add") {
                let trimmed = goalName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                repo.addPersonalGoal(to: game, named: trimmed)
                expanded.insert(TrackerSchemaJSON.personalGoalsID)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isGenerating: Bool { generation.isGenerating(game.id) }

    /// Drop the app-wide failure banner for THIS game — the inline error the
    /// user is looking at says the same thing. Successes are left alone: those
    /// carry a "ready" message worth seeing wherever you end up.
    private func dismissRedundantNotice() {
        guard let notice = generation.notice,
              notice.gameID == game.id, !notice.success else { return }
        generation.clearNotice()
    }

    /// Any tracker content beyond user-created Personal Goals?
    private var hasNonGoalContent: Bool {
        categories.contains { $0.id != TrackerSchemaJSON.personalGoalsID && !$0.items.isEmpty }
    }

    /// Library-wide default. Hardcoded until it can be remembered on
    /// ThemeSettings, which is frozen Schema V1 — a V2 item.
    private var defaultAction: TrackerGenerationAction { .fallbackDefault }

    private func start(_ action: TrackerGenerationAction) {
        // Only Replace can cost anything, so only Replace asks. Confirming an
        // append-only merge would be friction that teaches people to tap
        // through dialogs without reading them.
        if action == .replace, hasNonGoalContent {
            confirmingRegenerate = true
        } else {
            generation.generate(for: game, context: context, action: action)
        }
    }

    private func generate() {
        generation.generate(for: game, context: context, action: defaultAction)
    }

    // MARK: Merge summary

    /// What the last generation actually did. Shown in place rather than as a
    /// toast because the rescue offer needs to survive long enough to be read
    /// and acted on — a completed item the new tracker dropped is exactly the
    /// thing you don't want disappearing after three seconds.
    @ViewBuilder
    private func mergeSummary(_ outcome: Repository.TrackerMergeOutcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(LSTheme.accent)
                Text(summaryText(outcome))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Dismiss") { generation.clearOutcome(for: game.id) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            if !outcome.lostProgress.isEmpty {
                let names = outcome.lostProgress.prefix(3).map(\.name).joined(separator: ", ")
                let more = outcome.lostProgress.count > 3
                    ? " and \(outcome.lostProgress.count - 3) more" : ""
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(outcome.lostProgress.count) item\(outcome.lostProgress.count == 1 ? "" : "s") you'd finished aren't in the new tracker — \(names)\(more).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            repo.rescueAsPersonalGoals(outcome.lostProgress, for: game)
                            generation.clearOutcome(for: game.id)
                            expanded.insert(TrackerSchemaJSON.personalGoalsID)
                        } label: {
                            Label("Keep them as Personal Goals", systemImage: "pin")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(10)
        .background(LSTheme.accent.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func summaryText(_ outcome: Repository.TrackerMergeOutcome) -> String {
        var parts: [String] = []
        if outcome.added > 0 { parts.append("added \(outcome.added)") }
        if outcome.removed > 0 { parts.append("removed \(outcome.removed)") }
        // Worth saying out loud: this is the failure mode that used to be
        // silent, so the fix shouldn't be silent either.
        if outcome.migrated > 0 {
            parts.append("kept your progress on \(outcome.migrated) renamed item\(outcome.migrated == 1 ? "" : "s")")
        } else if outcome.renamed > 0 {
            parts.append("\(outcome.renamed) renamed")
        }
        return parts.isEmpty ? "Tracker updated." : "Tracker updated — \(parts.joined(separator: ", "))."
    }

    // MARK: Header

    private func header(_ cats: [TrackerCategoryDTO], states: [String: TrackerStateRecord]) -> some View {
        let allItems = cats.flatMap(\.items)
        let done = allItems.filter { states[$0.id]?.completed == true }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if !allItems.isEmpty {
                    Text("\(done)/\(allItems.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        hideCompleted.toggle()
                    } label: {
                        Image(systemName: hideCompleted ? "eye.slash.fill" : "eye")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .help("Hide completed")
                }
                if cats.contains(where: \.pending) {
                    Button {
                        hidePlanned.toggle()
                    } label: {
                        Image(systemName: hidePlanned ? "square.dashed" : "square.dashed.inset.filled")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .help(hidePlanned ? "Show planned categories" : "Hide planned categories")
                }
            }
            if !allItems.isEmpty {
                ProgressView(value: Double(done), total: Double(allItems.count))
                    .tint(LSTheme.accent)
            }
        }
    }

    /// A category that has been planned but not filled in.
    ///
    /// The skeleton a stepped generation leaves behind, and equally what
    /// sketching a tracker by hand produces. Shown as a real row with its own
    /// Generate button rather than an empty heading, because an empty heading
    /// reads as a bug and gives you nothing to act on.
    @ViewBuilder
    private func plannedCategoryRow(_ category: TrackerCategoryDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                if let count = category.plannedCount, category.counted {
                    // Too many to list, so this one fills as a single counter.
                    // Saying "about 900 items" here and then producing one row
                    // reads as a failure rather than as the intended answer.
                    Text("Planned · one counter up to \(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let count = category.plannedCount {
                    Text("Planned · about \(count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Planned — nothing generated yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            // Only ONE generation can run per game, so the other planned rows
            // are disabled rather than spinning: a spinner on a row nothing is
            // happening to is a lie, and it was the first thing this shipped.
            if generation.isGenerating(game.id, category: category.id) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    generation.generateCategory(category.id, named: category.name,
                                                expectedCount: category.plannedCount,
                                                for: game, context: context)
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(LSTheme.accent)
                .disabled(isGenerating)
            }
        }
        .padding(10)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contextMenu {
            moveActions(category)
            Divider()
            Button(role: .destructive) {
                repo.removePlannedCategory(from: game, categoryID: category.id)
            } label: { Label("Remove", systemImage: "trash") }
        }
    }

    // MARK: Category

    @ViewBuilder
    private func categoryView(_ category: TrackerCategoryDTO, states: [String: TrackerStateRecord],
                              gating: TrackerGating.Resolver) -> some View {
        let visibleItems = hideCompleted
            ? category.items.filter { states[$0.id]?.completed != true }
            : category.items
        if category.pending && category.items.isEmpty {
            plannedCategoryRow(category)
        } else if !visibleItems.isEmpty {
            let done = category.items.filter { states[$0.id]?.completed == true }.count
            DisclosureGroup(isExpanded: expansionBinding(category.id)) {
                Group {
                    if let groups = locationGroups(visibleItems) {
                        // "Koala Village" under all nine of its Heart Coins is
                        // the same word nine times. Hoisting it into a
                        // subheading says it once, and leaves the items as bare
                        // names — which then qualify for the column grid, so a
                        // long checklist collapses twice over.
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(groups, id: \.name) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(LSTheme.accent.opacity(0.9))
                                    itemsBody(group.items, category: category, states: states, gating: gating)
                                }
                            }
                        }
                    } else if isDense(visibleItems) {
                        // Short, detail-free items waste most of a row each.
                        // An adaptive grid self-tunes by available width rather
                        // than by item count: one column on a narrow phone with
                        // long names, two on a normal phone, three at the 640pt
                        // reading width used on iPad and Mac.
                        //
                        // 180 is a floor on the COLUMN, which is what keeps the
                        // tap target honest — packing more columns in would
                        // shrink rows toward unhittable, which is the opposite
                        // of the point.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180),
                                                     alignment: .leading)],
                                  alignment: .leading, spacing: 2) {
                            ForEach(visibleItems) { item in
                                itemRow(item, category: category, states: states, gating: gating)
                            }
                        }
                    } else {
                        VStack(spacing: 2) {
                            ForEach(visibleItems) { item in
                                itemRow(item, category: category, states: states, gating: gating)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(done)/\(category.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(done == category.items.count ? .green : .secondary)
                }
                .contentShape(.rect)
                .contextMenu {
                    Button {
                        renameText = category.name
                        renaming = (category.id, nil)
                    } label: { Label("Rename Category", systemImage: "pencil") }
                    Divider()
                    moveActions(category)
                    Divider()
                    Button(role: .destructive) {
                        removing = RemovalTarget(
                            categoryID: category.id, name: category.name,
                            cost: repo.removalCost(for: game, categoryID: category.id))
                    } label: { Label("Delete Category", systemImage: "trash") }
                }
            }
            .tint(.secondary)
        }
    }

    /// Move this category up, down, or straight to the top.
    ///
    /// Buttons rather than drag-to-reorder: these rows live in a VStack inside
    /// a scroll view, not a List, and "pin the thing I'm working on to the top"
    /// is the actual ask — which one press does and a drag doesn't.
    @ViewBuilder
    private func moveActions(_ category: TrackerCategoryDTO) -> some View {
        let ids = categories.map(\.id)
        let index = ids.firstIndex(of: category.id)
        Button {
            repo.moveCategoryToTop(category.id, in: game)
        } label: { Label("Move to Top", systemImage: "arrow.up.to.line") }
            .disabled(index == 0)
        Button {
            repo.moveCategory(category.id, in: game, by: -1)
        } label: { Label("Move Up", systemImage: "arrow.up") }
            .disabled(index == 0)
        Button {
            repo.moveCategory(category.id, in: game, by: 1)
        } label: { Label("Move Down", systemImage: "arrow.down") }
            .disabled(index == ids.count - 1)
    }

    /// Items grouped under their shared location, or nil when grouping wouldn't
    /// earn its keep.
    ///
    /// Only when every item has a location and the locations genuinely repeat —
    /// one heading per item would be worse than the repetition it replaces.
    /// Order follows first appearance, so an imported checklist stays in the
    /// order it was written rather than being alphabetised out of walkthrough
    /// order.
    private func locationGroups(_ items: [TrackerItemDTO])
        -> [(name: String, items: [TrackerItemDTO])]? {
        guard items.count >= 6,
              items.allSatisfy({ !($0.location ?? "").isEmpty }) else { return nil }
        var order: [String] = []
        var grouped: [String: [TrackerItemDTO]] = [:]
        for item in items {
            let key = item.location ?? ""
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        guard order.count >= 2, order.count <= items.count / 2 else { return nil }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// Rows for a set of items, in columns when they're simple enough.
    @ViewBuilder
    private func itemsBody(_ items: [TrackerItemDTO], category: TrackerCategoryDTO, states: [String: TrackerStateRecord],
                           gating: TrackerGating.Resolver) -> some View {
        if isDense(items, ignoringLocation: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                      alignment: .leading, spacing: 2) {
                ForEach(items) { itemRow($0, category: category, states: states, gating: gating, hideLocation: true) }
            }
        } else {
            VStack(spacing: 2) {
                ForEach(items) { itemRow($0, category: category, states: states, gating: gating, hideLocation: true) }
            }
        }
    }

    /// Whether a category's items are simple enough to sit side by side.
    ///
    /// Only when every visible item is a bare short name — no location, no
    /// description, no rank control. A single item with a two-line description
    /// would leave a ragged column beside a wall of text, which is worse than
    /// the scrolling it saves.
    private func isDense(_ items: [TrackerItemDTO], ignoringLocation: Bool = false) -> Bool {
        items.count >= 6 && items.allSatisfy { item in
            (ignoringLocation || item.location == nil)
                && (item.itemDescription?.isEmpty ?? true)
                && item.maxRank == nil
                && item.name.count <= 28
        }
    }

    /// Says the number. "This can't be undone" is true of everything and
    /// tells you nothing; "12 items, 5 of which you've made progress on" is
    /// the fact someone needs to decide with.
    private var removalWarning: String {
        guard let target = removing else { return "" }
        let scope = target.categoryID == nil
            ? "Removes the whole tracker for \(game.name)"
            : "Removes this category"
        if target.cost.isEmpty { return "\(scope). There's nothing in it yet." }
        var text = "\(scope) — \(target.cost.items) item\(target.cost.items == 1 ? "" : "s")"
        if target.cost.withProgress > 0 {
            text += ", \(target.cost.withProgress) of which you've made progress on"
        }
        return text + ". Your play sessions and completions are untouched, but this can't be undone."
    }

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    // MARK: Item row

    @ViewBuilder
    private func itemRow(_ item: TrackerItemDTO, category: TrackerCategoryDTO,
                         states: [String: TrackerStateRecord],
                         gating: TrackerGating.Resolver,
                         hideLocation: Bool = false) -> some View {
        let state = states[item.id]
        let done = state?.completed == true
        let hidden = item.hideUntilDiscovered && state?.revealed != true && !done

        HStack(alignment: .top, spacing: 4) {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                if hidden {
                    repo.revealTrackerItem(pt, itemID: item.id)
                } else if !done {
                    // Ask BEFORE, because afterwards it is advice about the
                    // past: this is the moment a questline ends or an ending
                    // is foreclosed, and the player is usually one tap from
                    // not knowing it happened.
                    let losing = gating.wouldLoseByCompleting(item)
                    if losing.isEmpty {
                        repo.setTrackerItem(pt, itemID: item.id, done: true)
                    } else {
                        confirmingLockout = LockoutPrompt(item: item, losing: losing)
                    }
                } else {
                    // The setter recomputes and saves internally — an extra
                    // recompute here doubled the parse/touch/save per tap.
                    repo.setTrackerItem(pt, itemID: item.id, done: false)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
                    .font(.body)
                    // The glyph is ~22pt; the thing you have to hit shouldn't
                    // be. Top-aligned so it still lines up with the first line
                    // of a multi-line row rather than centring against it.
                    .frame(width: 36, height: 44, alignment: .top)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hidden ? "Hidden — tap circle to reveal" : item.name)
                        .font(.subheadline)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(hidden ? AnyShapeStyle(.tertiary) : (done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                    if item.missable && !hidden {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Missable")
                    }
                }
                if !hidden, case .blocked(let needs) = gating.status(of: item) {
                    Label("Needs \(needs.joined(separator: ", "))", systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !hidden, case .lost(let to) = gating.status(of: item) {
                    Label("Closed off by \(to.joined(separator: ", "))",
                          systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.9))
                }
                if !hidden, !hideLocation, let location = item.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Descriptions that carry an "(Alt: …)" clause — Hades' Mirror
                // of Night does — get the alternative behind a chip instead of
                // running both variants together in one sentence.
                if !hidden, let description = item.itemDescription, !description.isEmpty {
                    AltDescription(text: description, tint: LSTheme.accent,
                                   selectedVariant: state?.selectedVariant) { variant in
                        let pt = repo.ensureDefaultPlaythrough(for: game)
                        repo.setTrackerVariant(pt, itemID: item.id, variant: variant)
                    }
                }
                // The user's own note, marked so it reads as theirs rather
                // than as more of whatever supplied the item.
                if !hidden, let note = item.note, !note.isEmpty {
                    Label(note, systemImage: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent.opacity(0.85))
                }
                if !hidden, let maxRank = item.maxRank {
                    rankControl(item, category: category, maxRank: maxRank,
                                current: state?.rank ?? 0)
                }
                if !hidden, let target = item.countTarget, target > 0 {
                    countControl(item, target: target, current: state?.count ?? 0)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .padding(.vertical, 3)
        // Dimmed rather than hidden: knowing a thing exists and is not yet
        // reachable is the point — hiding it would just look like a shorter
        // tracker.
        .opacity({ if case .available = gating.status(of: item) { return 1.0 } else { return 0.55 } }())
        .contextMenu {
            Button {
                editing = EditTarget(categoryID: category.id, itemID: item.id,
                                     name: item.name, location: item.location ?? "",
                                     note: item.note ?? "",
                                     countTarget: item.countTarget)
            } label: { Label("Edit Item", systemImage: "pencil") }
        }
    }

    /// Counting, for the things there are hundreds of.
    ///
    /// 900 koroks cannot be nine hundred rows — the tracker would be unusable
    /// and the generator would never produce it. One row that counts is how
    /// those games become trackable at all. Minus and plus are separated by
    /// the number itself so a mis-tap costs one, and holding is not required
    /// for the common case of "I found another one".
    private func countControl(_ item: TrackerItemDTO, target: Int, current: Int) -> some View {
        let pct = target > 0 ? Double(current) / Double(target) : 0
        return HStack(spacing: 10) {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.setTrackerCount(pt, itemID: item.id, count: current - 1, target: target)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(current <= 0)

            VStack(spacing: 3) {
                Text("\(current)/\(target)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .frame(width: 74)
                    .tint(LSTheme.accent)
            }

            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.setTrackerCount(pt, itemID: item.id, count: current + 1, target: target)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(current >= target)
        }
        .foregroundStyle(LSTheme.accent)
        .animation(.snappy, value: current)
    }

    /// Tap-to-set ranks. Replaces the old Stepper, which showed progress as a
    /// bare "0/5" and made a category of ranked items read as a form.
    private func rankControl(_ item: TrackerItemDTO, category: TrackerCategoryDTO,
                             maxRank: Int, current: Int) -> some View {
        RankPicker(
            display: RankDisplay.resolve(explicit: item.display,
                                         categoryName: category.name,
                                         maxRank: maxRank),
            current: current,
            maxRank: maxRank,
            rankNames: item.rankNames,
            tint: category.name.localizedCaseInsensitiveContains("keepsake") ? .pink : LSTheme.accent
        ) { newRank in
            let pt = repo.ensureDefaultPlaythrough(for: game)
            repo.setTrackerRank(pt, itemID: item.id,
                                rank: max(0, min(newRank, maxRank)), maxRank: maxRank)
        }
    }
}
