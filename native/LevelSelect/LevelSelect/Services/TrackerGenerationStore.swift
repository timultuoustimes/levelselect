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

/// A finished generation waiting on the user's decision.
struct PendingTrackerMerge: Sendable {
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

    /// Kick off generation for a game. No-op if one is already running for it,
    /// so double-tapping can't start two.
    /// Generate for one category only — the stepped unit.
    ///
    /// Works today against the existing whole-tracker generator: the payload
    /// comes back complete and only the named category is taken from it. That
    /// is wasteful of tokens and will be replaced by a per-category mode on
    /// the edge function, but it means filling a planned category is real now
    /// rather than after a backend deploy, and the app side can be shaped
    /// against something that actually runs.
    func generateCategory(_ categoryID: String, named categoryName: String,
                          for game: Game, context: ModelContext) {
        generate(for: game, context: context, action: .addNew,
                 scopedTo: (id: categoryID, name: categoryName))
    }

    func generate(for game: Game, context: ModelContext,
                  action: TrackerGenerationAction = .fallbackDefault,
                  scopedTo category: (id: String, name: String)? = nil) {
        let id = game.id
        guard tasks[id] == nil else { return }

        errors[id] = nil
        outcomes[id] = nil
        pending[id] = nil
        startedAt[id] = .now

        let name = game.name
        let igdbID = game.igdbID

        tasks[id] = Task { [weak self] in
            do {
                let jsonData = try await AITrackerService.generate(gameName: name, igdbID: igdbID)
                // Progress rows need a playthrough; make sure one exists before
                // the schema lands, so a never-played game can still be set up.
                let repo = Repository(context)
                repo.ensureDefaultPlaythrough(for: game)

                if let category {
                    // One category, replaced in place; everything else in the
                    // tracker is left exactly as it is.
                    self?.outcomes[id] = repo.applyGeneratedSchema(
                        for: game, jsonData: jsonData,
                        mode: .replaceCategories(ids: [category.id]))
                    // The scoped merge matches the incoming payload by id and
                    // then by name; a generator that answered with different
                    // headings entirely matches neither and leaves the
                    // category exactly as it was. Saying "ready" then would be
                    // a plain lie about an unchanged, still-empty category, so
                    // check what actually landed before claiming anything.
                    let filled = repo.trackerCategories(for: game)
                        .first { $0.id == category.id }?.items.isEmpty == false
                    self?.notice = GenerationNotice(
                        gameID: id, gameName: name, success: filled,
                        text: filled
                            ? "\(category.name) is ready in \(name)."
                            : "Nothing came back for \(category.name) in \(name). Try again, or rename it to match what the game calls it.")
                } else if action == .review, game.trackerSchema != nil {
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

    private func finish(_ id: UUID) {
        tasks[id] = nil
        startedAt[id] = nil
    }
}
