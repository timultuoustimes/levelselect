import Foundation
import SwiftData
import Observation

/// Owns in-flight AI tracker generations, so they survive navigation.
///
/// Generation takes a minute or two. It used to live in `TrackerSectionView`'s
/// `@State`, which meant the *work* kept running (an unstructured `Task` isn't
/// cancelled when a view disappears) but the *progress* died with the view:
/// navigate away and back and it looked idle, and any error vanished
/// unseen. Hoisting it here — same pattern as `PersistenceMonitor.shared` and
/// `SyncStatusMonitor.shared` — means the spinner, the elapsed timer, and the
/// failure message are all still there when you come back.
///
/// Scope note: this survives navigation *within* the app. It does not survive
/// the app being suspended — `URLSession.shared` uses a default configuration,
/// which iOS suspends on backgrounding. Outliving that needs a background
/// URLSession or a poll-for-a-job-id backend; deliberately not built yet.
/// What pressing the generate button should do with the result.
///
/// Surfaced as the button's own wording so the action is never a surprise,
/// and overridable per press — the default suits most games, but "this
/// tracker is terrible, replace the lot without showing me anything" wants to
/// be one tap away, not buried in settings.
enum TrackerGenerationAction: String, CaseIterable, Identifiable, Sendable {
    /// Append-only. Cannot remove anything, cannot lose progress.
    case addNew
    /// Stop and show what would change; nothing is written until you say so.
    case review
    /// Incoming wins outright. Personal Goals still survive.
    case replace

    var id: String { rawValue }

    /// The default until a remembered preference exists — that needs a field
    /// on ThemeSettings, which is frozen Schema V1, so it's a V2 item. Add-only
    /// is the safe default: it's the one mode that cannot cost you anything.
    static let fallbackDefault: TrackerGenerationAction = .addNew

    var label: String {
        switch self {
        case .addNew:  "Add New Only"
        case .review:  "Review Changes"
        case .replace: "Replace Everything"
        }
    }

    /// Used as the button's title, so the button says what it will do.
    func buttonTitle(regenerating: Bool) -> String {
        guard regenerating else { return "Generate with AI" }
        switch self {
        case .addNew:  return "Regenerate & Add New"
        case .review:  return "Regenerate & Review"
        case .replace: return "Regenerate & Replace"
        }
    }

    var systemImage: String {
        switch self {
        case .addNew:  "plus.circle"
        case .review:  "list.bullet.rectangle"
        case .replace: "arrow.triangle.2.circlepath"
        }
    }

    var detail: String {
        switch self {
        case .addNew:  "Keeps everything you have and adds what's missing."
        case .review:  "Shows what would change before anything is written."
        case .replace: "Discards the current tracker content."
        }
    }

    var mergeMode: TrackerMergeMode? {
        switch self {
        case .addNew:  .addAll
        case .replace: .replace
        case .review:  nil        // resolved by the review screen
        }
    }
}

/// What an in-flight run is doing — which decides both what spins and what the
/// waiting card is allowed to claim is happening.
enum GenerationKind: Equatable, Sendable {
    /// The whole tracker.
    case full
    /// The shape only: category names and rough sizes, no items.
    case plan
    /// One named category.
    case category(id: String, name: String)
    /// Regenerating the lists under the categories you already have.
    case refresh(names: [String])
}

/// What a whole-tracker generation asks for. Tim, 09-14: the regenerate menu
/// offers both, because they answer different questions.
enum GenerationScope: Sendable {
    /// The lists under your own categories — "Update My Lists".
    case yourLists
    /// The whole game, new categories and all — "Find New Categories", which is
    /// what Regenerate & Add New always did before it was scoped.
    case wholeGame
}

/// Where a Generate All Planned run is: `done` of `total` planned categories.
struct PlannedBatchProgress: Equatable, Sendable {
    var done: Int
    var total: Int
}

/// A finished generation waiting on the user's decision.
struct PendingTrackerMerge: Identifiable, Sendable {
    let id = UUID()
    let incoming: Data
    let diff: TrackerDiff
    /// The categories this generation was limited to. Empty for a whole-game
    /// generation. A Replace chosen on the review screen reads it, so a
    /// reviewed refresh replaces only what came back instead of deleting every
    /// category the limited answer never mentioned.
    var inScope: [TrackerCategoryDTO] = []
}

/// A generation that finished (or failed) — surfaced app-wide, because the
/// user has usually navigated away during the minute it takes. Without this,
/// a background failure was completely silent and a success only showed if
/// you happened to wander back to that game's tracker.
struct GenerationNotice: Identifiable, Sendable {
    let id = UUID()
    let gameID: UUID
    let gameName: String
    let success: Bool
    let text: String
}

@MainActor
@Observable
final class TrackerGenerationStore {
    static let shared = TrackerGenerationStore()

    /// When each in-flight generation started, keyed by game id. The date
    /// drives the elapsed-time readout — a minute of waiting is much easier to
    /// sit through when you can see it counting.
    private(set) var startedAt: [UUID: Date] = [:]
    /// Last failure per game, kept until dismissed or a retry begins.
    private(set) var errors: [UUID: String] = [:]

    /// What the in-flight run is actually doing, per game.
    ///
    /// Started as "which category is being filled" — without it, the only
    /// "is it running" signal was per-GAME, so pressing Generate on one planned
    /// category spun the spinner on every planned category at once. It also
    /// decides what the waiting card says: a plan is not "reading the guide",
    /// and neither is filling one category of a game.
    private(set) var kinds: [UUID: GenerationKind] = [:]

    /// The most recent finished/failed generation, for the app-wide banner.
    private(set) var notice: GenerationNotice?

    /// Generations that finished but haven't been applied — the Review path.
    private(set) var pending: [UUID: PendingTrackerMerge] = [:]
    /// What the last applied merge did, kept until dismissed so the summary
    /// (and the rescue offer) can be shown after the spinner goes away.
    private(set) var outcomes: [UUID: Repository.TrackerMergeOutcome] = [:]

    /// A Generate All Planned run's position, per game. `kinds` still names
    /// the category being filled right now, so its row is the one that spins.
    private(set) var batches: [UUID: PlannedBatchProgress] = [:]

    private var tasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func isGenerating(_ gameID: UUID) -> Bool { startedAt[gameID] != nil }
    /// True only for the one category actually being filled right now.
    func isGenerating(_ gameID: UUID, category: String) -> Bool {
        if case .category(let id, _) = kinds[gameID] { return id == category }
        return false
    }
    func kind(for gameID: UUID) -> GenerationKind { kinds[gameID] ?? .full }
    func startDate(for gameID: UUID) -> Date? { startedAt[gameID] }
    func error(for gameID: UUID) -> String? { errors[gameID] }
    func pendingMerge(for gameID: UUID) -> PendingTrackerMerge? { pending[gameID] }
    func outcome(for gameID: UUID) -> Repository.TrackerMergeOutcome? { outcomes[gameID] }
    func batch(for gameID: UUID) -> PlannedBatchProgress? { batches[gameID] }

    func clearError(for gameID: UUID) { errors[gameID] = nil }
    func clearNotice() { notice = nil }
    func clearOutcome(for gameID: UUID) { outcomes[gameID] = nil }
    /// Walking away from the review screen throws the generated result away.
    func discardPending(for gameID: UUID) { pending[gameID] = nil }

    /// Apply a result the user reviewed, on the terms they picked.
    func applyPending(for game: Game, context: ModelContext, mode: TrackerMergeMode) {
        guard let merge = pending[game.id] else { return }
        pending[game.id] = nil
        let repo = Repository(context)
        repo.ensureDefaultPlaythrough(for: game)
        // The review screen's Replace on a limited refresh used to be a full
        // Replace of an answer holding only your filled lists — which deletes
        // every other category, planned ones included. Same confinement as a
        // Replace chosen straight from the menu.
        outcomes[game.id] = repo.applyGeneratedSchema(
            for: game, jsonData: merge.incoming,
            mode: Self.scoped(mode, inScope: merge.inScope, incoming: merge.incoming))
    }

    /// Ask what this game's tracker should be divided into, and write the
    /// answer down as empty planned categories.
    ///
    /// Nothing is generated here — that's the point. The reply is a handful of
    /// headings and rough sizes, so it arrives in seconds and can be corrected
    /// (renamed, deleted, added to) before a minute of generation is spent on
    /// any of it. Categories that clash with ones already there are refused by
    /// the repository and reported as skipped rather than silently dropped.
    func suggestCategories(for game: Game, context: ModelContext) {
        let id = game.id
        guard tasks[id] == nil else { return }
        begin(id, kind: .plan)

        let name = game.name
        let igdbID = game.igdbID

        tasks[id] = Task { [weak self] in
            do {
                let proposed = try await AITrackerService.plan(gameName: name, igdbID: igdbID)
                let repo = Repository(context)
                var added = 0
                for category in proposed
                where repo.addPlannedCategory(to: game, named: category.name,
                                              plannedCount: category.plannedCount,
                                              counted: category.counted) {
                    added += 1
                }
                let skipped = proposed.count - added
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: added > 0,
                    text: added > 0
                        ? "Planned \(added) categor\(added == 1 ? "y" : "ies") for \(name)\(skipped > 0 ? " (\(skipped) already there)" : ""). Fill them in one at a time."
                        : "\(name) already has every category the planner suggested.")
            } catch is CancellationError {
            } catch {
                self?.errors[id] = error.localizedDescription
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: false,
                    text: "Couldn't plan a tracker for \(name).")
            }
            self?.finish(id)
        }
    }

    /// Generate one category — the stepped unit.
    ///
    /// This used to call the whole-tracker generator and throw away everything
    /// except the named category: correct, absurdly wasteful, and on a big game
    /// it simply timed out before returning. It now asks the backend for that
    /// category alone.
    func generateCategory(_ categoryID: String, named categoryName: String,
                          expectedCount: Int? = nil, counted: Bool = false,
                          regenerating: Bool = false,
                          for game: Game, context: ModelContext) {
        let id = game.id
        guard tasks[id] == nil else { return }
        begin(id, kind: .category(id: categoryID, name: categoryName))

        let name = game.name
        let igdbID = game.igdbID

        tasks[id] = Task { [weak self] in
            do {
                guard let result = try await self?.fill(
                    categoryID: categoryID, named: categoryName,
                    expectedCount: expectedCount, counted: counted,
                    game: game, gameName: name, igdbID: igdbID, context: context)
                else { return }
                let outcome = result.outcome
                let filled = result.filled
                self?.outcomes[id] = outcome
                let text: String
                if regenerating {
                    // A filled category is "filled" whether or not the answer
                    // matched it, so emptiness proves nothing here. What the
                    // merge changed is the honest report, and "came back the
                    // same" is true both of an identical answer and of one
                    // that didn't match — without claiming to know which.
                    let changed = outcome.added + outcome.removed + outcome.renamed
                    text = changed > 0
                        ? "The \(categoryName) list is regenerated in \(name)."
                        : "The \(categoryName) list came back the same in \(name)."
                } else {
                    text = filled
                        ? "\(categoryName) is ready in \(name)."
                        : "Nothing came back for \(categoryName) in \(name). Try again, or rename it to match what the game calls it."
                }
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: filled, text: text)
            } catch is CancellationError {
            } catch {
                self?.errors[id] = error.localizedDescription
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: false,
                    text: "Couldn't fill \(categoryName) in \(name).")
            }
            self?.finish(id)
        }
    }

    /// Fetch one category and merge it in by itself — the unit a single
    /// Generate and Generate All Planned are both made of, so they can't drift.
    private func fill(categoryID: String, named categoryName: String,
                      expectedCount: Int?, counted: Bool,
                      game: Game, gameName: String, igdbID: Int?,
                      context: ModelContext) async throws
        -> (outcome: Repository.TrackerMergeOutcome, filled: Bool) {
        let jsonData = try await AITrackerService.generateCategory(
            gameName: gameName, categoryName: categoryName,
            expectedCount: expectedCount, counted: counted, igdbID: igdbID)
        let repo = Repository(context)
        repo.ensureDefaultPlaythrough(for: game)
        let outcome = repo.applyGeneratedSchema(
            for: game, jsonData: jsonData,
            mode: .replaceCategories(ids: [categoryID]))
        // The scoped merge matches the incoming payload by id and then by
        // name; an answer with a different heading matches neither and leaves
        // the category exactly as it was. Saying "ready" then would be a plain
        // lie about a still-empty category, so check what actually landed.
        let filled = repo.trackerCategories(for: game)
            .first { $0.id == categoryID }?.items.isEmpty == false
        return (outcome, filled)
    }

    /// The categories Generate All Planned fills: planned, and still empty.
    static func plannedCategories(_ categories: [TrackerCategoryDTO]) -> [TrackerCategoryDTO] {
        categories.filter { $0.pending && $0.items.isEmpty }
    }

    /// Fill every planned category, one after another.
    ///
    /// Tim, 09-14: *"skip planned, and yes add Generate All Planned."* Not one
    /// big request — that is the 150s timeout plans exist to avoid — but the
    /// same one-category fill each Generate button does, in turn.
    ///
    /// The tracker is re-read before every step, so a plan deleted or filled
    /// by hand mid-run is skipped rather than overwritten. One failure doesn't
    /// stop the rest; Stop does. Same scope limit as every generation here:
    /// it survives moving around the app, not the app being backgrounded.
    func generateAllPlanned(for game: Game, context: ModelContext) {
        let id = game.id
        guard tasks[id] == nil else { return }
        let queue = Self.plannedCategories(Repository(context).trackerCategories(for: game))
        guard let first = queue.first else { return }
        begin(id, kind: .category(id: first.id, name: first.name))
        batches[id] = PlannedBatchProgress(done: 0, total: queue.count)

        let name = game.name
        let igdbID = game.igdbID
        let queueIDs = queue.map(\.id)

        tasks[id] = Task { [weak self] in
            var filled: [String] = []
            var failed: [String] = []
            var added = 0

            for (index, categoryID) in queueIDs.enumerated() {
                guard let self, !Task.isCancelled else { break }
                self.batches[id] = PlannedBatchProgress(done: index, total: queueIDs.count)
                guard let category = Repository(context).trackerCategories(for: game)
                    .first(where: { $0.id == categoryID }),
                      category.pending, category.items.isEmpty
                else { continue }
                self.kinds[id] = .category(id: category.id, name: category.name)
                // The waiting card's captions run off elapsed time. Timed from
                // the start of the whole run, every list after the first ninety
                // seconds would open on "Long list — still going…".
                self.startedAt[id] = .now
                do {
                    let result = try await self.fill(
                        categoryID: category.id, named: category.name,
                        expectedCount: category.plannedCount, counted: category.counted,
                        game: game, gameName: name, igdbID: igdbID, context: context)
                    added += result.outcome.added
                    if result.filled { filled.append(category.name) } else { failed.append(category.name) }
                } catch {
                    // A cancelled request can surface as a URL error rather
                    // than CancellationError, so ask the task, not the error.
                    if Task.isCancelled { break }
                    failed.append(category.name)
                }
            }

            let stopped = Task.isCancelled
            if added > 0 {
                self?.outcomes[id] = Repository.TrackerMergeOutcome(added: added)
            }
            let noun: (Int) -> String = { $0 == 1 ? "category" : "categories" }
            let text: String
            if stopped {
                text = "Stopped after generating lists for \(filled.count) planned \(noun(filled.count)) in \(name)."
            } else if failed.isEmpty {
                text = "Generated lists for \(filled.count) planned \(noun(filled.count)) in \(name)."
            } else {
                let attempted = filled.count + failed.count
                text = "Generated lists for \(filled.count) of \(attempted) planned \(noun(attempted)) in \(name). Nothing came back for \(failed.joined(separator: ", "))."
            }
            if !stopped || !filled.isEmpty {
                self?.notice = GenerationNotice(gameID: id, gameName: name,
                                                success: !filled.isEmpty, text: text)
            }
            self?.finish(id)
        }
    }

    /// Kick off generation for a game. No-op if one is already running for it,
    /// so double-tapping can't start two.
    func generate(for game: Game, context: ModelContext,
                  action: TrackerGenerationAction = .fallbackDefault,
                  scope: GenerationScope = .yourLists) {
        let id = game.id
        guard tasks[id] == nil else { return }

        let name = game.name
        let igdbID = game.igdbID
        // Update My Lists asks for the lists under your categories; Find New
        // Categories asks for the whole game. With nothing to limit it to — a
        // first generation, or a tracker that is only plans — both ask for the
        // whole game, as a generation always did.
        let inScope = scope == .yourLists
            ? Self.regenerationCategories(Repository(context).trackerCategories(for: game))
            : []
        let requested = inScope.map(Self.requested)
        begin(id, kind: inScope.isEmpty ? .full : .refresh(names: inScope.map(\.name)))

        tasks[id] = Task { [weak self] in
            do {
                let jsonData = try await AITrackerService.generate(
                    gameName: name, igdbID: igdbID, categories: requested.isEmpty ? nil : requested)
                // Progress rows need a playthrough; make sure one exists before
                // the schema lands, so a never-played game can still be set up.
                let repo = Repository(context)
                repo.ensureDefaultPlaythrough(for: game)

                if action == .review, game.trackerSchema != nil {
                    // Hold the result and let the user decide. Nothing is
                    // written until they do.
                    // On a limited refresh, the lists that didn't come back
                    // can't be removed by any choice on the review screen, so
                    // the preview mustn't list them as losses.
                    var untouched = Set<String>()
                    if case .replaceCategories(let replaced) =
                        Self.scoped(.replace, inScope: inScope, incoming: jsonData) {
                        untouched = Set(repo.trackerCategories(for: game).map(\.id))
                            .subtracting(replaced)
                    }
                    self?.pending[id] = PendingTrackerMerge(
                        incoming: jsonData,
                        diff: repo.previewGeneratedSchema(for: game, jsonData: jsonData,
                                                          untouched: untouched),
                        inScope: inScope)
                    self?.notice = GenerationNotice(
                        gameID: id, gameName: name, success: true,
                        text: inScope.isEmpty
                            ? "\(name)'s tracker is ready to review."
                            : "\(name)'s updated lists are ready to review.")
                } else {
                    // A first generation has nothing to review or merge against,
                    // so Review collapses to a plain install.
                    var mode = action.mergeMode ?? .addAll
                    // A refresh that replaces replaces only what came back.
                    // A full Replace removes every category the payload doesn't
                    // mention — right when the payload was the whole game, and
                    // quietly destructive when it was your own list and the
                    // model dropped one of them.
                    mode = Self.scoped(mode, inScope: inScope, incoming: jsonData)
                    self?.outcomes[id] = repo.applyGeneratedSchema(
                        for: game, jsonData: jsonData, mode: mode)
                    self?.notice = GenerationNotice(
                        gameID: id, gameName: name, success: true,
                        text: inScope.isEmpty
                            ? "\(name)'s tracker is ready."
                            : "\(name)'s lists are updated.")
                }
            } catch is CancellationError {
                // Cancelled deliberately — not a failure worth surfacing.
            } catch {
                self?.errors[id] = error.localizedDescription
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: false,
                    text: "Tracker generation failed for \(name).")
            }
            self?.finish(id)
        }
    }

    /// What a category is, as a request: its name, how big it is, and whether
    /// it's a single running total. One rule for both "Regenerate This
    /// Category" and a whole-tracker refresh, so they can't disagree.
    static func requested(_ category: TrackerCategoryDTO) -> AITrackerService.RequestedCategory {
        if category.pending {
            return .init(name: category.name, expectedCount: category.plannedCount,
                         counted: category.counted)
        }
        let counter = category.items.count == 1 && (category.items.first?.countTarget ?? 0) > 0
        return .init(name: category.name,
                     expectedCount: counter ? category.items.first?.countTarget : category.items.count,
                     counted: counter)
    }

    /// Which of a tracker's categories a regeneration asks for.
    ///
    /// Not Personal Goals, a pasted (locked) list, or a RetroAchievements set:
    /// every merge mode already keeps those, they are the user's or another
    /// source's content, and asking a generator to rewrite them is how they'd
    /// come back duplicated.
    ///
    /// Not a planned category either. Tim, 09-14: *"skip planned."* Plans fill
    /// one at a time because a whole game in one request ran past the 150s
    /// edge limit — nine planned Hollow Knight lists are ~170 items — so
    /// folding them into a regeneration would bring that timeout straight
    /// back. They fill from their own Generate buttons, or Generate All Planned.
    static func regenerationScope(_ categories: [TrackerCategoryDTO]) -> [AITrackerService.RequestedCategory] {
        regenerationCategories(categories).map(requested)
    }

    static func regenerationCategories(_ categories: [TrackerCategoryDTO]) -> [TrackerCategoryDTO] {
        categories.filter { category in
            category.id != TrackerSchemaJSON.personalGoalsID
                && !category.locked && !category.isImportedSet
                && !category.pending
        }
    }

    /// A Replace on a limited refresh replaces only the lists that came back.
    ///
    /// A full Replace removes every category the payload doesn't mention: right
    /// when the payload is the whole game, and quietly destructive when it is
    /// your own lists and the model dropped one. Any other mode, or a
    /// whole-game generation (`inScope` empty), passes through unchanged.
    static func scoped(_ mode: TrackerMergeMode, inScope: [TrackerCategoryDTO],
                       incoming: Data) -> TrackerMergeMode {
        guard case .replace = mode, !inScope.isEmpty else { return mode }
        let returned = Set(TrackerSchemaJSON.categories(from: incoming)
            .map { TrackerMerge.matchKey($0.name) })
        return .replaceCategories(ids: Set(inScope
            .filter { returned.contains(TrackerMerge.matchKey($0.name)) }
            .map(\.id)))
    }

    /// Cancel an in-flight generation (user backed out of waiting).
    func cancel(for gameID: UUID) {
        tasks[gameID]?.cancel()
        finish(gameID)
    }

    /// Clear the last run's leftovers and mark this one as started.
    private func begin(_ id: UUID, kind: GenerationKind) {
        errors[id] = nil
        outcomes[id] = nil
        pending[id] = nil
        batches[id] = nil
        startedAt[id] = .now
        kinds[id] = kind
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
        startedAt[id] = nil
        kinds[id] = nil
        batches[id] = nil
    }
}
