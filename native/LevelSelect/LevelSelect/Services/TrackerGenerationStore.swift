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

    private var tasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func isGenerating(_ gameID: UUID) -> Bool { startedAt[gameID] != nil }
    func startDate(for gameID: UUID) -> Date? { startedAt[gameID] }
    func error(for gameID: UUID) -> String? { errors[gameID] }

    func clearError(for gameID: UUID) { errors[gameID] = nil }

    /// Kick off generation for a game. No-op if one is already running for it,
    /// so double-tapping can't start two.
    func generate(for game: Game, context: ModelContext) {
        let id = game.id
        guard tasks[id] == nil else { return }

        errors[id] = nil
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
                repo.setGeneratedSchema(for: game, jsonData: jsonData)
            } catch is CancellationError {
                // Cancelled deliberately — not a failure worth surfacing.
            } catch {
                self?.errors[id] = error.localizedDescription
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
