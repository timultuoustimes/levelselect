#if DEV_TOOLS   // developer-only; never in a Release build
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
        ///
        /// **nil means "resolve by name".** Unreleased games have no id worth
        /// pinning by hand — and pinning a *guessed* one is the worse failure,
        /// because a wrong id looks exactly like a right one. The seed report
        /// names every game that came in this way so a bad match is caught
        /// rather than quietly shipped.
        var igdbID: Int? = nil
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

        // **The wishlist.** Mostly unannounced-to-unreleased on purpose: the
        // ids are pinned like every other seed, and for a reason the name
        // fallback demonstrated: searching "The Legend of Zelda: Ocarina of
        // Time" returned a fan project called "Unreal Engine The Legend of
        // Zelda: Ocarina of Time" ahead of the 2026 remake. These came from
        // Tim's own library, so each one is an entry a person already chose.
        //
        // wishlist's three shelves are Coming soon / No date yet / Out now,
        // and the countdown, the releases widget and the reminder all key off
        // a real date. A wishlist of games that already shipped exercises none
        // of it. Owned by nobody and played for zero hours, because that is
        // what wanting a game looks like.
        .init(igdbID:  52189, name: "Grand Theft Auto VI",        platform: "PlayStation 5",          status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 338104, name: "The Duskbloods",             platform: "Nintendo Switch 2",      status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 325602, name: "Onimusha: Way of the Sword", platform: "PlayStation 5",          status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 405460, name: "The Legend of Zelda: Ocarina of Time", platform: "Nintendo Switch 2", status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 299593, name: "Promise Mascot Agency",      platform: "Nintendo Switch",        status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 361826, name: "Denshattack!",               platform: "Nintendo Switch",        status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 388341, name: "Future Knight",              platform: "PC (Microsoft Windows)", status: .wishlist, rating: nil, ownership: [], hours: 0),
        // Three Tim had added to the demo store by hand, promoted into the
        // seed because they shoot well: all three were still weeks out when he
        // asked for them, so "Coming soon" fills properly and the countdowns
        // read as real numbers rather than "today".
        //
        // Being hand-added is why they kept surviving "Empty demo library",
        // which removes what this seeder marked. Seeded, they carry the marker
        // and go with everything else.
        //
        // Dated releases are perishable in a way the rest of this list is not
        // — Onimusha above was three days out when it was added and has
        // already shipped. That is fine, and partly the point: the wishlist
        // wants both shelves populated. But if "Coming soon" ever comes up
        // empty in a capture, this block is why, and the fix is newer ids.
        .init(igdbID: 366896, name: "Fire Emblem: Fortune's Weave", platform: "Nintendo Switch 2",    status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 397817, name: "Graveyard Keeper II",         platform: "Nintendo Switch 2",     status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 225582, name: "Control Resonant",            platform: "Mac",                   status: .wishlist, rating: nil, ownership: [], hours: 0),
        // Out already, which the shelf needs too: "Out now" is one of the
        // three, and a wishlist of nothing but unreleased games never draws it.
        .init(igdbID: 381237, name: "Orbitals",                   platform: "Nintendo Switch",        status: .wishlist, rating: nil, ownership: [], hours: 0),
        .init(igdbID: 404724, name: "Blood Dungeon",              platform: "PC (Microsoft Windows)", status: .wishlist, rating: nil, ownership: [], hours: 0),
    ]

    /// The pinned ids, for the tests that guard this list.
    ///
    /// A wrong id does not fail — it quietly seeds a different game, and the
    /// capture looks fine until someone reads it. So the numbers are what gets
    /// checked, not the names.
    static var seededIGDBIDs: [Int] { seeds.compactMap(\.igdbID) }

    /// Create the demo library. Network is used for IGDB metadata; without it
    /// the games are still created, just without cover art.
    @discardableResult
    static func seed(context: ModelContext) async -> String {
        let repo = Repository(context)
        var created = 0
        var withCovers = 0
        var byName: [String: Game] = [:]

        var bySearch: [String] = []
        var unmatched: [String] = []

        for (rank, seed) in seeds.enumerated() {
            // Look up by pinned id where there is one — see Seed.igdbID.
            var igdb: IGDBGame?
            if let id = seed.igdbID {
                igdb = try? await IGDBService.lookup(id: id)
            } else if let hit = (try? await IGDBService.search(name: seed.name))?.first {
                igdb = hit
                // Report the name IGDB actually returned, not the one asked
                // for. "Future Knight" matching a 1986 ZX Spectrum game is the
                // failure this line exists to make visible.
                bySearch.append(hit.name == seed.name ? seed.name
                                                      : "\(seed.name) → \(hit.name)")
            } else {
                unmatched.append(seed.name)
            }
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
                addSessions(repo: repo, game: game, hours: seed.hours, rank: rank)
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
        addHadesProgress(repo: repo, game: byName["Hades"])
        addRuns(repo: repo, game: byName["Hades"])
        addCollection(repo: repo, games: ["Stardew Valley", "Celeste", "Sonic the Hedgehog 2"].compactMap { byName[$0] })

        PersistenceMonitor.shared.commit(context)
        var report = "Demo library ready: \(created) games (\(withCovers) with IGDB art), "
            + "sessions, a tracker, runs, and a collection."
        if !bySearch.isEmpty {
            report += "\n\nMatched by name, so worth checking: " + bySearch.joined(separator: ", ") + "."
        }
        if !unmatched.isEmpty {
            report += "\n\nIGDB had nothing for: " + unmatched.joined(separator: ", ")
                + ". Added without art."
        }
        return report
    }

    /// **A week-one library: the one every reviewer and new user has.**
    ///
    /// The demo library is generous, and eight months of use means nobody
    /// has seen the app with three games and nothing finished since February.
    /// That is where it breaks: Replay's thin periods, badges with nothing to
    /// date, charts over one week. Fable's 1.0 plan, step 4: three games, four
    /// sessions, one memory, no finishes, one range of imported hours.
    ///
    /// **Empties the whole demo store first**, not just what the seeder made:
    /// the first try kept the old demo's consoles, badge ledger and
    /// hand-added memories, and a three-game library claimed eight badges,
    /// "Five machines" and four memories (09-21). Refuses to run anywhere but
    /// the demo file.
    @discardableResult
    static func seedWeekOne(context: ModelContext) async -> String {
        guard isDemoStore(context) else { return "Only in the demo library." }
        purge(context: context)
        clearEverythingElse(context: context)
        let repo = Repository(context)
        let day: TimeInterval = 86_400

        // Pinned ids from the main seed list.
        let picks: [(id: Int, name: String, platform: String, status: GameStatus)] = [
            (14593, "Hollow Knight", "Nintendo Switch", .playing),
            (17000, "Stardew Valley", "Mac", .playing),
            (1802, "Chrono Trigger", "Super Nintendo Entertainment System", .backlog),
        ]
        var byName: [String: Game] = [:]
        for pick in picks {
            let game: Game
            if let igdb = try? await IGDBService.lookup(id: pick.id) {
                game = repo.addGame(from: igdb, platform: pick.platform, status: pick.status)
            } else {
                game = repo.addGame(name: pick.name, status: pick.status)
            }
            game.platforms = [pick.platform]
            game.legacyID = marker
            game.ownership = [Ownership.digital.rawValue]
            byName[pick.name] = game
        }

        // Four sessions, all inside the last week: three of Hollow Knight,
        // one of Stardew. Human lengths.
        if let hk = byName["Hollow Knight"] {
            let pt = repo.ensureDefaultPlaythrough(for: hk)
            for (daysAgo, hours) in [(6.0, 1.1), (3.0, 2.2), (1.0, 0.7)] {
                repo.logManualSession(on: pt, duration: hours * 3600,
                                      date: Date.now.addingTimeInterval(-daysAgo * day))
            }
            // One memory, dated to the day.
            let memory = Memory(title: "Finally beat the Mantis Lords")
            memory.body = "Took all evening. Bowed back."
            memory.game = hk
            memory.legacyID = marker
            repo.saveMemory(memory, on: Date.now.addingTimeInterval(-3 * day),
                            precision: "day", words: nil)
        }
        if let stardew = byName["Stardew Valley"] {
            let pt = repo.ensureDefaultPlaythrough(for: stardew)
            repo.logManualSession(on: pt, duration: 1.5 * 3600,
                                  date: Date.now.addingTimeInterval(-5 * day))
            // The imported lump, placed across three years — what a Steam
            // library brings in on day one.
            repo.setCarriedOver(38 * 3600, on: pt)
            let year = Calendar.current.component(.year, from: .now)
            repo.setCarriedOverSpans([CarriedOverSpan(seconds: 38 * 3600,
                                                      fromYear: year - 5, toYear: year - 3)],
                                     on: pt)
        }

        PersistenceMonitor.shared.commit(context)
        return "Week-one library ready: 3 games, 4 sessions, 1 memory, no finishes, "
            + "and 38 imported hours placed across three years."
    }

    /// A believable play history: sessions of a human length, spread over
    /// months, with almost nothing inside the last week.
    ///
    /// The old version put six sessions at 1, 4.5, 8, 11.5, 15 and 18.5 days
    /// ago and split each game's WHOLE lifetime across them. Two things
    /// followed, and both were nonsense. Stardew Valley's 63 hours landed
    /// inside nineteen days. And because the first two sessions carried half
    /// the total and both fell inside the 7-day window, Home reported 138h 40m
    /// played this week — 5.8 days of continuous play, out of a possible 7.
    ///
    /// Now: sessions are about two and a half hours each, roughly nine days
    /// apart, running backwards from when the game was last touched. Only the
    /// two most recently played games have been opened inside the last week,
    /// which puts "this week" at a handful of hours rather than most of it.
    private static func addSessions(repo: Repository, game: Game, hours: Double, rank: Int) {
        let pt = repo.ensureDefaultPlaythrough(for: game)

        // When this game was last played. Only the first two are inside the
        // week; everything else trails off into months, which is what a real
        // library of fourteen games looks like.
        let lastPlayed: Double = switch rank {
        case 0:  1.5
        case 1:  4.0
        default: Double(rank) * 11 + 9
        }

        // ~2.5 hours a sitting, so the count follows from the total rather
        // than the total being crammed into a fixed six.
        let count = max(3, min(24, Int((hours / 2.5).rounded())))
        let each = hours / Double(count)

        for index in 0..<count {
            // Nine days apart: a game you come back to most weeks, not one you
            // played for a fortnight straight and abandoned.
            let daysAgo = lastPlayed + Double(index) * 9
            repo.logManualSession(
                on: pt,
                duration: each * 3600,
                date: Date.now.addingTimeInterval(-daysAgo * 86_400))
        }
        // NO open session for a paused game.
        //
        // This used to leave the most recent session open, reasoning that "a
        // paused game should look paused". But those are two different
        // paused: the STATUS means you have set the game aside, while a paused
        // SESSION is a timer stopped mid-play. An open session put all three
        // shelved games into "Also Running" — the shelf that exists to show
        // live timers — each frozen at 01:00:00, so every demo library opened
        // looking like three timers had been left going.
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

    /// Partial progress on the built-in Hades tracker — it ships with the app
    /// (IGDB 113112) and attaches automatically, but an all-zero tracker is a
    /// poor screenshot. Ranks and unlocks here look like ~30 hours in.
    private static func addHadesProgress(repo: Repository, game: Game?) {
        guard let game, let pt = game.activePlaythrough else { return }

        // Weapon aspects: the starting aspects unlocked and levelled, the
        // hidden ones still untouched.
        for (id, rank) in [("blade-zagreus", 5), ("blade-nemesis", 3),
                           ("spear-zagreus", 4), ("spear-achilles", 2),
                           ("shield-zagreus", 3), ("bow-zagreus", 2)] {
            repo.setTrackerRank(pt, itemID: id, rank: rank, maxRank: 5)
        }
        // Keepsakes: the early-game gifts, a couple maxed.
        for (id, rank) in [("old-spiked-collar", 3), ("myrmidon-bracer", 2),
                           ("black-shawl", 3), ("pierced-butterfly", 1),
                           ("bone-hourglass", 2), ("chthonic-coin-purse", 1)] {
            repo.setTrackerRank(pt, itemID: id, rank: rank, maxRank: 3)
        }
        for id in ["battie", "mort", "rib"] {
            repo.setTrackerItem(pt, itemID: id, done: true)
        }
        // Mirror of Night: the talents you buy first.
        for (id, rank, max) in [("mirror-death-defiance", 2, 3),
                                ("mirror-shadow-presence", 3, 5),
                                ("mirror-chthonic-vitality", 5, 5),
                                ("mirror-dark-regeneration", 2, 5),
                                ("mirror-stygian-soul", 1, 1)] {
            repo.setTrackerRank(pt, itemID: id, rank: rank, maxRank: max)
        }
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
    ///
    /// **It says what it left behind**, because "Empty demo library" reads
    /// like it empties the library and it does not — it removes what the
    /// SEEDER made, and a game you added by hand while in demo mode has no
    /// marker and stays. Tim hit exactly that: he emptied the demo library,
    /// saw "All (0)", and four hand-added wishlist games were still there
    /// putting Switch 2 and Mac in the systems menu. Nothing was wrong with
    /// the deletion; the report just stopped short of the fact that explained
    /// what he was looking at.
    ///
    /// **Tombstoned first, deleted for good a moment later.**
    ///
    /// This used to hard-delete on the spot, and whatever screen was drawing
    /// a demo game at that instant (Home's Continue Playing card, under the
    /// Settings sheet) read a property off a deleted row and crashed.
    /// "Load a week-one library" found it, because it empties the library
    /// with Home already populated (09-21). A tombstone is what every query
    /// filters on, so the screens let go of the rows first; the rows
    /// themselves go once nothing holds them. A tombstone that outlives the
    /// app (quit within the second) is swept at the start of the next purge.
    @discardableResult
    static func purge(context: ModelContext) -> String {
        sweepTombstones(context: context)
        let now = Date.now
        var removed = 0
        let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        for game in games where game.legacyID == marker && game.deletedAt == nil {
            game.deletedAt = now
            removed += 1
        }
        for collection in ((try? context.fetch(FetchDescriptor<GameCollection>())) ?? [])
        where collection.legacyID == marker && collection.deletedAt == nil {
            collection.deletedAt = now
        }
        // A game's memories outlive it (the relationship nullifies), so the
        // week-one seed's memory goes by its own marker.
        for memory in ((try? context.fetch(FetchDescriptor<Memory>())) ?? [])
        where memory.legacyID == marker && memory.deletedAt == nil {
            memory.deletedAt = now
        }
        PersistenceMonitor.shared.commit(context)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            sweepTombstones(context: context)
        }
        return message(removed: removed, kept: kept(among: games))
    }

    private static func isDemoStore(_ context: ModelContext) -> Bool {
        let demo = LevelSelectStore.demoStoreURL.standardizedFileURL
        return context.container.configurations.contains { $0.url.standardizedFileURL == demo }
    }

    /// Tombstones everything left in the demo store after a purge — the
    /// hand-added, the consoles, the badges — so the week-one seed starts
    /// from nothing. The badge ledger goes too, so the first-run fill runs
    /// again against three games, which is the thing to check.
    private static func clearEverythingElse(context: ModelContext) {
        let now = Date.now
        for game in (try? context.fetch(FetchDescriptor<Game>())) ?? [] where game.deletedAt == nil {
            game.deletedAt = now
            game.legacyID = marker
        }
        for memory in (try? context.fetch(FetchDescriptor<Memory>())) ?? [] where memory.deletedAt == nil {
            memory.deletedAt = now
            memory.legacyID = marker
        }
        for collection in (try? context.fetch(FetchDescriptor<GameCollection>())) ?? []
        where collection.deletedAt == nil {
            collection.deletedAt = now
            collection.legacyID = marker
        }
        for console in (try? context.fetch(FetchDescriptor<Console>())) ?? [] where console.deletedAt == nil {
            console.deletedAt = now
        }
        for badge in (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? [] where badge.deletedAt == nil {
            badge.deletedAt = now
        }
        PersistenceMonitor.shared.commit(context)
    }

    /// Hard-deletes what an earlier purge tombstoned.
    private static func sweepTombstones(context: ModelContext) {
        var any = false
        for game in ((try? context.fetch(FetchDescriptor<Game>())) ?? [])
        where game.legacyID == marker && game.deletedAt != nil {
            context.delete(game); any = true
        }
        for collection in ((try? context.fetch(FetchDescriptor<GameCollection>())) ?? [])
        where collection.legacyID == marker && collection.deletedAt != nil {
            context.delete(collection); any = true
        }
        for memory in ((try? context.fetch(FetchDescriptor<Memory>())) ?? [])
        where memory.legacyID == marker && memory.deletedAt != nil {
            context.delete(memory); any = true
        }
        if any { PersistenceMonitor.shared.commit(context) }
    }

    /// Live games in this store that the seeder did not create.
    static func kept(among games: [Game]) -> Int {
        games.filter { $0.deletedAt == nil && $0.legacyID != marker }.count
    }

    /// Separated from `purge` so the sentence can be checked without a store.
    static func message(removed: Int, kept: Int) -> String {
        let first = "Removed \(removed) demo game(s) and their history."
        guard kept > 0 else { return first }
        // Named as the user's own, because they are — this is the one line
        // standing between "the button is broken" and "oh, I added those".
        return first + " \(kept) game(s) you added yourself are still here; "
            + "the seeder only removes what it made."
    }
}
#endif
