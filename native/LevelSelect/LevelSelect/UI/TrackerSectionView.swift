import SwiftUI
import SwiftData

/// Objective tracker: schema-driven checklist (categories → items) with
/// per-playthrough state. Personal Goals are user-added items in the same
/// schema. Everything syncs via CloudKit like the rest of the model.
struct TrackerSectionView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @State private var hideCompleted = false
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
    @State private var builtinAvailable = false
    @State private var confirmingUseBuiltin = false

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

    var body: some View {
        let cats = categories
        let states = stateByItem
        VStack(alignment: .leading, spacing: 12) {
            header(cats, states: states)

            if let started = generation.startDate(for: game.id) {
                GeneratingTrackerView(startedAt: started) {
                    generation.cancel(for: game.id)
                }
                .padding(.vertical, 2)
            } else if cats.isEmpty {
                Text("No tracker yet — generate one with AI or add a personal goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Existing content stays visible while regenerating — hiding it
            // made a regenerate look like the tracker had been wiped.
            ForEach(cats) { category in
                categoryView(category, states: states)
            }

            if let outcome = generation.outcome(for: game.id), !outcome.isNoOp {
                mergeSummary(outcome)
            }

            if let error = generation.error(for: game.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 4)
                    Button("Dismiss") { generation.clearError(for: game.id) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 18) {
                Button {
                    goalName = ""
                    addingGoal = true
                } label: {
                    Label("Add Personal Goal", systemImage: "plus.circle")
                        .font(.subheadline)
                }
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

                Button {
                    importingList = true
                } label: {
                    Label("Paste a List", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                }

                if builtinAvailable && !usingBuiltin {
                    Button {
                        confirmingUseBuiltin = true
                    } label: {
                        Label("Use Built-in Tracker", systemImage: "checkmark.seal")
                            .font(.subheadline)
                    }
                    .disabled(isGenerating)
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
        .sheet(isPresented: $importingList) {
            TrackerListImportView(game: game)
        }
        .sheet(item: $editing) { target in
            TrackerItemEditView(game: game, target: target)
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
            }
            if !allItems.isEmpty {
                ProgressView(value: Double(done), total: Double(allItems.count))
                    .tint(LSTheme.accent)
            }
        }
    }

    // MARK: Category

    @ViewBuilder
    private func categoryView(_ category: TrackerCategoryDTO, states: [String: TrackerStateRecord]) -> some View {
        let visibleItems = hideCompleted
            ? category.items.filter { states[$0.id]?.completed != true }
            : category.items
        if !visibleItems.isEmpty {
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
                                    itemsBody(group.items, category: category, states: states)
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
                                itemRow(item, category: category, states: states)
                            }
                        }
                    } else {
                        VStack(spacing: 2) {
                            ForEach(visibleItems) { item in
                                itemRow(item, category: category, states: states)
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
                }
            }
            .tint(.secondary)
        }
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
    private func itemsBody(_ items: [TrackerItemDTO], category: TrackerCategoryDTO, states: [String: TrackerStateRecord]) -> some View {
        if isDense(items, ignoringLocation: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                      alignment: .leading, spacing: 2) {
                ForEach(items) { itemRow($0, category: category, states: states, hideLocation: true) }
            }
        } else {
            VStack(spacing: 2) {
                ForEach(items) { itemRow($0, category: category, states: states, hideLocation: true) }
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
                         hideLocation: Bool = false) -> some View {
        let state = states[item.id]
        let done = state?.completed == true
        let hidden = item.hideUntilDiscovered && state?.revealed != true && !done

        HStack(alignment: .top, spacing: 4) {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                if hidden {
                    repo.revealTrackerItem(pt, itemID: item.id)
                } else {
                    // The setter recomputes and saves internally — an extra
                    // recompute here doubled the parse/touch/save per tap.
                    repo.setTrackerItem(pt, itemID: item.id, done: !done)
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
                if !hidden, !hideLocation, let location = item.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Descriptions that carry an "(Alt: …)" clause — Hades' Mirror
                // of Night does — get the alternative behind a chip instead of
                // running both variants together in one sentence.
                if !hidden, let description = item.itemDescription, !description.isEmpty {
                    AltDescription(text: description, tint: LSTheme.accent)
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
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                editing = EditTarget(categoryID: category.id, itemID: item.id,
                                     name: item.name, location: item.location ?? "",
                                     note: item.note ?? "")
            } label: { Label("Edit Item", systemImage: "pencil") }
        }
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
