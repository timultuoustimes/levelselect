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
}

/// A finished generation waiting on the user's decision.
struct PendingTrackerMerge: Identifiable, Sendable {
    let id = UUID()
    let incoming: Data
    let diff: TrackerDiff
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
        outcomes[game.id] = repo.applyGeneratedSchema(
            for: game, jsonData: merge.incoming, mode: mode)
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
                          for game: Game, context: ModelContext) {
        let id = game.id
        guard tasks[id] == nil else { return }
        begin(id, kind: .category(id: categoryID, name: categoryName))

        let name = game.name
        let igdbID = game.igdbID

        tasks[id] = Task { [weak self] in
            do {
                let jsonData = try await AITrackerService.generateCategory(
                    gameName: name, categoryName: categoryName,
                    expectedCount: expectedCount, counted: counted, igdbID: igdbID)
                let repo = Repository(context)
                repo.ensureDefaultPlaythrough(for: game)
                self?.outcomes[id] = repo.applyGeneratedSchema(
                    for: game, jsonData: jsonData,
                    mode: .replaceCategories(ids: [categoryID]))
                // The scoped merge matches the incoming payload by id and then
                // by name; an answer with a different heading matches neither
                // and leaves the category exactly as it was. Saying "ready"
                // then would be a plain lie about a still-empty category, so
                // check what actually landed before claiming anything.
                let filled = repo.trackerCategories(for: game)
                    .first { $0.id == categoryID }?.items.isEmpty == false
                self?.notice = GenerationNotice(
                    gameID: id, gameName: name, success: filled,
                    text: filled
                        ? "\(categoryName) is ready in \(name)."
                        : "Nothing came back for \(categoryName) in \(name). Try again, or rename it to match what the game calls it.")
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

    /// Kick off generation for a game. No-op if one is already running for it,
    /// so double-tapping can't start two.
    func generate(for game: Game, context: ModelContext,
                  action: TrackerGenerationAction = .fallbackDefault) {
        let id = game.id
        guard tasks[id] == nil else { return }
        begin(id, kind: .full)

        let name = game.name
        let igdbID = game.igdbID

        tasks[id] = Task { [weak self] in
            do {
                let jsonData = try await AITrackerService.generate(gameName: name, igdbID: igdbID)
                // Progress rows need a playthrough; make sure one exists before
                // the schema lands, so a never-played game can still be set up.
                let repo = Repository(context)
                repo.ensureDefaultPlaythrough(for: game)

                if action == .review, game.trackerSchema != nil {
                    // Hold the result and let the user decide. Nothing is
                    // written until they do.
                    self?.pending[id] = PendingTrackerMerge(
                        incoming: jsonData,
                        diff: repo.previewGeneratedSchema(for: game, jsonData: jsonData))
                    self?.notice = GenerationNotice(
                        gameID: id, gameName: name, success: true,
                        text: "\(name)'s tracker is ready to review.")
                } else {
                    // A first generation has nothing to review or merge against,
                    // so Review collapses to a plain install.
                    let mode = action.mergeMode ?? .addAll
                    self?.outcomes[id] = repo.applyGeneratedSchema(
                        for: game, jsonData: jsonData, mode: mode)
                    self?.notice = GenerationNotice(
                        gameID: id, gameName: name, success: true,
                        text: "\(name)'s tracker is ready.")
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
        startedAt[id] = .now
        kinds[id] = kind
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
        startedAt[id] = nil
        kinds[id] = nil
    }
}
