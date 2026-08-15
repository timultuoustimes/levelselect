#if LEGACY_IMPORT   // developer-only, same gate as the legacy import
import Foundation
import SwiftData

/// Builds a small, presentable library for screenshots and video capture.
///
/// The problem this solves: the only library on hand is Tim's real one — 159
/// games with genuinely messy session and tracker data — and that's exactly
/// the personal data the beta work stripped out of shipping builds. Capturing
/// marketing shots from it would put it right back in public.
///
/// So this creates ~12 widely-recognized games, looked up through IGDB so the
/// covers and metadata are real, with plausible play history: sessions spread
/// over the past few weeks, ratings, ownership, a collection, a populated
/// tracker, and a run history for the roguelike. Deterministic — no randomness
/// — so retakes frame identically to the first pass.
@MainActor
enum DemoLibrarySeeder {
    static let marker = "__ls_demo__"

    private struct Seed {
        /// Pinned IGDB id. Search alone is unreliable for a demo that has to
        /// look identical every time: "Hades" returns a 1995 game before
        /// Supergiant's, and "Disco Elysium" leads with the Game Boy Edition.
        let igdbID: Int
        let name: String
        let platform: String
        let status: GameStatus
        let rating: Int?
        let ownership: [Ownership]
        /// Hours of play history to fabricate, spread across sessions.
        let hours: Double
    }

    /// Deliberately broad: a few current, a few finished, a few untouched, and
    /// a retro corner so the "By System" shelf has something to show.
    private static let seeds: [Seed] = [
        .init(igdbID:  14593, name: "Hollow Knight",        platform: "Nintendo Switch", status: .playing,   rating: 5, ownership: [.digital],            hours: 41.2),
        .init(igdbID: 113112, name: "Hades",                platform: "Nintendo Switch", status: .playing,   rating: 5, ownership: [.digital],            hours: 28.6),
        .init(igdbID: 251833, name: "Balatro",              platform: "Mac",             status: .playing,   rating: 4, ownership: [.digital],            hours: 19.4),
        .init(igdbID:  17000, name: "Stardew Valley",       platform: "Mac",             status: .paused,    rating: 5, ownership: [.digital],            hours: 63.0),
        .init(igdbID:  26472, name: "Disco Elysium",        platform: "PC (Microsoft Windows)", status: .paused, rating: 4, ownership: [.digital],        hours: 12.8),
        .init(igdbID: 191435, name: "Animal Well",          platform: "Nintendo Switch", status: .paused,    rating: 4, ownership: [.digital],            hours: 6.5),
        .init(igdbID:  26226, name: "Celeste",              platform: "Nintendo Switch", status: .completed, rating: 5, ownership: [.physical, .digital], hours: 22.1),
        .init(igdbID:  11737, name: "Outer Wilds",          platform: "PC (Microsoft Windows)", status: .completed, rating: 5, ownership: [.digital],     hours: 31.7),
        .init(igdbID:   4438, name: "Sonic the Hedgehog 2", platform: "Sega Mega Drive/Genesis", status: .completed, rating: 4, ownership: [.physical, .emulated], hours: 4.3),
        .init(igdbID:   1103, name: "Super Metroid",        platform: "Super Nintendo Entertainment System", status: .backlog, rating: nil, ownership: [.emulated], hours: 0),
        .init(igdbID:   1802, name: "Chrono Trigger",       platform: "Super Nintendo Entertainment System", status: .backlog, rating: nil, ownership: [.emulated], hours: 0),
        .init(igdbID:  23733, name: "Tunic",                platform: "Nintendo Switch", status: .queued,    rating: nil, ownership: [.digital],          hours: 0),
        // Current releases, so the demo doesn't read as a 2018 time capsule.
        .init(igdbID: 305152, name: "Clair Obscur: Expedition 33", platform: "PlayStation 5", status: .playing, rating: 5, ownership: [.digital], hours: 24.9),
        .init(igdbID: 366893, name: "Pokémon Pokopia",     platform: "Nintendo Switch 2", status: .playing, rating: nil, ownership: [.physical], hours: 8.7),
    ]

    /// Create the demo library. Network is used for IGDB metadata; without it
    /// the games are still created, just without cover art.
    @discardableResult
    static func seed(context: ModelContext) async -> String {
        let repo = Repository(context)
        var created = 0
        var withCovers = 0
        var byName: [String: Game] = [:]

        for seed in seeds {
            // Look up by pinned id, not by name — see Seed.igdbID.
            let igdb = try? await IGDBService.lookup(id: seed.igdbID)
            let game: Game
            if let igdb {
                game = repo.addGame(from: igdb, platform: seed.platform, status: seed.status)
                withCovers += 1
            } else {
                game = repo.addGame(name: seed.name, status: seed.status)
            }
            // Pin the platform to exactly one. IGDB lists every platform a game
            // shipped on, and PlatformPreference then picks its own leader —
            // which scattered the demo across Switch 2 / PC and hid the retro
            // console icons. One platform each keeps the Systems shelf
            // deterministic and shows off the hardware art.
            game.platforms = [seed.platform]
            game.legacyID = marker          // how purge finds these again
            game.rating = seed.rating
            game.ownership = seed.ownership.map(\.rawValue)
            game.pinned = (seed.name == "Hollow Knight")
            byName[seed.name] = game
            created += 1

            if seed.hours > 0 {
                addSessions(repo: repo, game: game, hours: seed.hours, status: seed.status)
            }
        }

        // A second playthrough on one game, so the per-playthrough vs
        // game-total split is actually visible (SessionControlsView only shows
        // "All playthroughs" once a game has more than one).
        if let hk = byName["Hollow Knight"] {
            let steelSoul = repo.addPlaythrough(to: hk, named: "Steel Soul")
            repo.logManualSession(on: steelSoul, duration: 3 * 3600 + 1500,
                                  date: Date.now.addingTimeInterval(-2 * 86_400))
            // Leave the original as the active one — it's the populated story.
            if let first = hk.livePlaythroughs.first {
                repo.setActivePlaythrough(first, for: hk)
            }
        }

        // Attach hand-built trackers (Hades ships one keyed to IGDB 113112,
        // with weapon aspects, keepsakes, companions, Mirror of Night, and a
        // run template) before the hand-written demo tracker below.
        BuiltinTrackers.installMissing(context: context)

        addTracker(repo: repo, game: byName["Hollow Knight"])
        addRuns(repo: repo, game: byName["Hades"])
        addCollection(repo: repo, games: ["Stardew Valley", "Celeste", "Sonic the Hedgehog 2"].compactMap { byName[$0] })

        PersistenceMonitor.shared.commit(context)
        return "Demo library ready: \(created) games (\(withCovers) with IGDB art), sessions, a tracker, runs, and a collection."
    }

    /// Sessions spread backwards from today, newest first, so Home's
    /// "recently played" ordering looks natural.
    private static func addSessions(repo: Repository, game: Game, hours: Double, status: GameStatus) {
        let pt = repo.ensureDefaultPlaythrough(for: game)
        // Fixed shape rather than random, so repeat runs look identical.
        let split: [Double] = [0.28, 0.22, 0.18, 0.14, 0.10, 0.08]
        for (index, share) in split.enumerated() {
            let duration = hours * 3600 * share
            let daysAgo = Double(index) * 3.5 + 1
            let start = Date.now.addingTimeInterval(-daysAgo * 86_400)
            repo.logManualSession(on: pt, duration: duration, date: start)
        }
        // A paused game should look paused: leave the most recent session open.
        if status == .paused {
            let session = repo.startSession(on: pt, at: Date.now.addingTimeInterval(-5_400))
            repo.pauseSession(session, at: Date.now.addingTimeInterval(-1_800))
        }
    }

    /// A small hand-written schema so the tracker page has real structure
    /// without spending an AI generation.
    private static func addTracker(repo: Repository, game: Game?) {
        guard let game else { return }
        let schema: [String: Any] = [
            "schemaVersion": 1,
            "categories": [
                [
                    "id": "bosses", "name": "Main Bosses", "type": "checklist",
                    "items": [
                        ["id": "b-false-knight", "name": "False Knight"],
                        ["id": "b-hornet-1", "name": "Hornet Protector"],
                        ["id": "b-mantis-lords", "name": "Mantis Lords"],
                        ["id": "b-soul-master", "name": "Soul Master"],
                        ["id": "b-broken-vessel", "name": "Broken Vessel"],
                        ["id": "b-nosk", "name": "Nosk", "missable": true],
                        ["id": "b-hollow-knight", "name": "The Hollow Knight", "hideUntilDiscovered": true],
                    ],
                ],
                [
                    "id": "charms", "name": "Charms", "type": "collectibles",
                    "items": [
                        ["id": "c-wayward-compass", "name": "Wayward Compass", "location": "Forgotten Crossroads"],
                        ["id": "c-gathering-swarm", "name": "Gathering Swarm", "location": "Dirtmouth"],
                        ["id": "c-stalwart-shell", "name": "Stalwart Shell", "location": "Forgotten Crossroads"],
                        ["id": "c-soul-catcher", "name": "Soul Catcher", "location": "Ancestral Mound"],
                        ["id": "c-quick-focus", "name": "Quick Focus", "location": "Salubra"],
                        ["id": "c-grubsong", "name": "Grubsong", "location": "Grubfather"],
                    ],
                ],
                [
                    "id": "nail", "name": "Nail Upgrades", "type": "leveled",
                    "items": [
                        ["id": "n-nail", "name": "Nail", "maxRank": 4,
                         "rankNames": ["Old Nail", "Sharpened", "Channelled", "Coiled", "Pure"]],
                    ],
                ],
            ],
            "completionNotes": "112% requires all charms, nail arts, and both endings.",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: schema) else { return }
        repo.setGeneratedSchema(for: game, jsonData: data)

        // Partial progress reads better in a screenshot than empty or complete.
        guard let pt = game.activePlaythrough else { return }
        for id in ["b-false-knight", "b-hornet-1", "b-mantis-lords", "b-soul-master"] {
            repo.setTrackerItem(pt, itemID: id, done: true)
        }
        for id in ["c-wayward-compass", "c-gathering-swarm", "c-stalwart-shell", "c-grubsong"] {
            repo.setTrackerItem(pt, itemID: id, done: true)
        }
        repo.setTrackerRank(pt, itemID: "n-nail", rank: 2, maxRank: 4)
        repo.recomputeProgress(game)
    }

    /// A believable roguelike record: more losses than wins, improving later.
    private static func addRuns(repo: Repository, game: Game?) {
        guard let game else { return }
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let history: [(weapon: String, aspect: String, outcome: RunOutcome, minutes: Double)] = [
            ("Stygian Blade", "Nemesis", .failure, 18),
            ("Heart-Seeking Bow", "Chiron", .failure, 24),
            ("Shield of Chaos", "Zeus", .failure, 31),
            ("Stygian Blade", "Arthur", .success, 42),
            ("Twin Fists", "Talos", .failure, 27),
            ("Adamant Rail", "Eldest", .success, 38),
            ("Shield of Chaos", "Beowulf", .success, 45),
        ]
        for (index, run) in history.enumerated() {
            let started = Date.now.addingTimeInterval(-Double(index) * 2.5 * 86_400)
            repo.logRun(
                on: pt,
                fields: ["weapon": run.weapon, "aspect": run.aspect],
                outcome: run.outcome,
                started: started,
                duration: run.minutes * 60,
                notes: nil
            )
        }
    }

    private static func addCollection(repo: Repository, games: [Game]) {
        guard !games.isEmpty else { return }
        let collection = repo.createCollection(name: "Comfort Games")
        collection.legacyID = marker
        for game in games {
            repo.setMembership(collection, game: game, member: true)
        }
    }

    /// Remove everything this seeder created. Cascade deletes take the
    /// playthroughs, sessions, runs, and tracker rows with the games.
    @discardableResult
    static func purge(context: ModelContext) -> String {
        var removed = 0
        for game in ((try? context.fetch(FetchDescriptor<Game>())) ?? []) where game.legacyID == marker {
            context.delete(game)
            removed += 1
        }
        for collection in ((try? context.fetch(FetchDescriptor<GameCollection>())) ?? [])
        where collection.legacyID == marker {
            context.delete(collection)
        }
        PersistenceMonitor.shared.commit(context)
        return "Removed \(removed) demo game(s) and their history."
    }
}
#endif
