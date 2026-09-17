import Foundation
import SwiftData

/// Import a library from a CSV file.
///
/// This is the on-ramp: people arriving from Gamery, Backloggd, a spreadsheet,
/// or LevelSelect's own export need a way in, and CSV is the only path with no
/// API, no auth, no rate limits, and no partner terms. It also carries the
/// match-review step every future importer (Steam, RetroAchievements) will
/// need, so that work isn't spent twice.
///
/// Deliberately forgiving about shape: column names vary wildly between apps,
/// so headers are matched by a set of aliases rather than a fixed schema, and
/// anything unrecognized is ignored rather than failing the import.
enum CSVImport {

    // MARK: Parsing

    /// A single parsed row, already mapped onto the fields we care about.
    struct Row: Identifiable {
        let id = UUID()
        var name: String
        /// The first of `platforms` — the one a single-platform caller uses.
        var platform: String?
        /// **Every platform the cell names.** Gamery writes a game owned on two
        /// systems as one cell, `Xbox,Mac`, and reading that as one name made
        /// a console called "Xbox,Mac" (Tim, 2026-09-11).
        var platforms: [String] = []
        var status: GameStatus?
        var rating: Int?
        var notes: String?
        var hoursPlayed: Double?
        /// The IGDB id, when the export carries one (Gamery does, on every
        /// row). A title is a guess at a game; an id IS the game, so a row
        /// with one is matched by it and never flagged.
        var igdbID: Int? = nil
        /// Original line number, for error messages that a human can act on.
        var line: Int
        /// Why this row starts unticked in the review, when an importer has a
        /// reason to think it isn't wanted — a played Steam demo counts as owned.
        /// Shown beside the row; the user can still tick it.
        var skipReason: String? = nil
        /// True when the source can't say which machine a game was played on,
        /// so the review offers a choice. Xbox lists every machine a game runs
        /// on: a 360 game also names the Series consoles.
        var offersPlatformChoice = false
        /// The source's machines, in the order to prefer them.
        var platformChoices: [String] = []
        /// Machines offered only when you have a record for one, and never
        /// picked for you: any Steam game might be on your Steam Deck, and
        /// nothing says which are.
        var ownedOnlyChoices: [String] = []
        /// Headsets offered, when you have one, for a game IGDB lists on any
        /// of them. A SteamVR game plays on a Quest or a Vive as well as the
        /// Index that IGDB's "SteamVR" folds to. Never picked for you.
        var vrChoices: [String] = []
        /// The source knows which machines it was played on (PlayStation
        /// does), so the row keeps them; the choices only add to them — a
        /// PlayStation VR game can be on the headset too.
        var platformsKnown = false
        /// Where the row lands when you have none of the choices.
        var fallbackPlatform: String? = nil
        /// The source calls it a game but has little to show for it — Xbox
        /// with no achievements. The review unticks it unless IGDB knows the
        /// title exactly: companion apps like Halo Waypoint.
        var mayBeAnApp = false
        /// A game you already have. Importing it adds the row's consoles to
        /// the ones you own it on and changes nothing else.
        var existingGameID: UUID? = nil
        /// Box art from the source, kept when IGDB has none for the game.
        var coverURL: String? = nil
        /// Take IGDB's game only when the title matches exactly. itch.io is
        /// mostly games IGDB has never heard of, and its nearest hit is
        /// usually an unrelated game with a similar name.
        var exactMatchOnly = false

        /// The row lands on this console alone.
        mutating func choosePlatform(_ platform: String?) {
            self.platform = platform
            platforms = platform.map { [$0] } ?? []
        }

        /// Add or remove one console, keeping at least one. Several mark the
        /// game owned on each, which is the point: the same game on the 360
        /// and the Switch.
        mutating func togglePlatform(_ option: String, order: [String]) {
            var picked = platforms
            if let index = picked.firstIndex(of: option) {
                guard picked.count > 1 else { return }
                picked.remove(at: index)
            } else {
                picked.append(option)
            }
            platforms = order.filter(picked.contains) + picked.filter { !order.contains($0) }
            platform = platforms.first
        }
    }

    /// What the review offers for a row: the source's consoles, then any
    /// other machine the matched game is on that you have a record for (Mac,
    /// the Switch — Minecraft Dungeons signs in to Xbox there
    /// too, and Xbox doesn't say so), then your hardware from
    /// `ownedOnlyChoices` and, for a VR game, your `vrChoices`, then PC.
    static func platformChoices(for row: Row, matchPlatforms: [String], owned: Set<String>) -> [String] {
        guard row.offersPlatformChoice else { return row.platformChoices }
        let isPC = { (name: String) in PlatformKey.canonical(name) == "PC" }
        var seen = Set(row.platformChoices.map(PlatformKey.canonical))
        let others = matchPlatforms.filter {
            let key = PlatformKey.canonical($0)
            return !isPC($0) && owned.contains(key) && seen.insert(key).inserted
        }
        let vrKeys = Set(row.vrChoices.map(PlatformKey.canonical))
        let isVR = matchPlatforms.contains { vrKeys.contains(PlatformKey.canonical($0)) }
        let hardware = (row.ownedOnlyChoices + (isVR ? row.vrChoices : [])).filter {
            let key = PlatformKey.canonical($0)
            return owned.contains(key) && seen.insert(key).inserted
        }
        return row.platformChoices.filter { !isPC($0) } + others + hardware
            + row.platformChoices.filter(isPC)
    }

    /// The row on the first choice you have a record for, or its fallback. A
    /// record counts even when it's marked former: the question is which
    /// machine you played it on. `ownedOnlyChoices` are offered, never picked.
    static func preferOwnedPlatform(_ row: Row, choices: [String], owned: Set<String>) -> Row {
        var row = row
        let hardware = Set((row.ownedOnlyChoices + row.vrChoices).map(PlatformKey.canonical))
        row.choosePlatform(choices.first {
            let key = PlatformKey.canonical($0)
            return owned.contains(key) && !hardware.contains(key)
        } ?? row.fallbackPlatform)
        return row
    }

    /// The machines a review can set every row to at once, each with how many
    /// rows offer it, in the order they first appear.
    static func bulkPlatforms(_ choices: [[String]]) -> [(platform: String, rows: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for list in choices where list.count > 1 {
            var inRow = Set<String>()
            for key in list.map(PlatformKey.canonical) where inRow.insert(key).inserted {
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            }
            for name in list where names[PlatformKey.canonical(name)] == nil {
                names[PlatformKey.canonical(name)] = name
            }
        }
        return order.map { (names[$0] ?? $0, counts[$0] ?? 0) }
    }

    // MARK: Title matching

    /// Two titles are the same when they differ only in case, accents,
    /// punctuation or ™ ® ©. Compared exactly, "Brink™" was not "Brink", and
    /// the review fell back to IGDB's first hit: "Brink of Consciousness".
    static func sameTitle(_ a: String, _ b: String) -> Bool {
        TrackerMerge.matchKey(a) == TrackerMerge.matchKey(b)
    }

    /// The consoles a title search should favor: the one the source says the
    /// game was made for (Xbox's original console, Steam's PC), else the ones
    /// the row names. "Modern Warfare® 3" from a 360 is the 2011 game, not
    /// the 2023 "Modern Warfare III" IGDB ranks first.
    static func matchHints(for row: Row) -> [String] {
        row.fallbackPlatform.map { [$0] } ?? row.platforms
    }

    static func isOn(_ game: IGDBGame, _ hints: [String]) -> Bool {
        let keys = Set(hints.map(PlatformKey.canonical))
        return game.platforms.contains { keys.contains(PlatformKey.canonical($0)) }
    }

    /// IGDB's hits with the ones on a hinted console first, order otherwise kept.
    static func ranked(_ hits: [IGDBGame], hints: [String]) -> [IGDBGame] {
        guard !hints.isEmpty else { return hits }
        return hits.filter { isOn($0, hints) } + hits.filter { !isOn($0, hints) }
    }

    /// The hit to start a row on: the exact title on a hinted console, then the
    /// exact title anywhere, then the first hit on a hinted console, then the
    /// first hit. `exact` says whether the title matched.
    static func bestMatch(_ hits: [IGDBGame], name: String, hints: [String]) -> (game: IGDBGame?, exact: Bool) {
        let exact = hits.filter { sameTitle($0.name, name) }
        if let game = exact.first(where: { isOn($0, hints) }) ?? exact.first { return (game, true) }
        return (ranked(hits, hints: hints).first, false)
    }

    /// How long to wait before the next IGDB request so an import stays
    /// under the proxy's 60 a minute (55, leaving room for anything else the
    /// app asks meanwhile). `recent` is when the last requests went out.
    static func paceDelay(now: Date, recent: [Date], limit: Int = 55) -> TimeInterval {
        let window = recent.filter { now.timeIntervalSince($0) < 60 }.sorted()
        guard window.count >= limit else { return 0 }
        return max(0, 60 - now.timeIntervalSince(window[window.count - limit]))
    }

    /// The name to search IGDB for. Its search doesn't fold the marks, so
    /// "Assassin's Creed® III" found nothing at all.
    static func searchName(_ name: String) -> String {
        name.replacingOccurrences(of: "[™®©]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    struct ParseResult {
        var rows: [Row]
        var recognizedColumns: [String]
        var ignoredColumns: [String]
        /// Rows skipped because they had no usable title.
        var skippedLines: [Int]
    }

    /// Header aliases, lowercased. Covers Gamery, Backloggd, GG, Grouvee,
    /// HowLongToBeat exports, LevelSelect's own export, and plain spreadsheets.
    private static let aliases: [String: [String]] = [
        "name":     ["name", "title", "game", "game name", "game title"],
        "igdb":     ["igdb id", "igdb", "igdb_id", "igdbid"],
        "platform": ["platform", "console", "system", "device", "platforms",
                     "library platforms"],
        "status":   ["status", "state", "list", "shelf", "category", "progress"],
        "rating":   ["rating", "score", "stars", "my rating", "user rating"],
        "notes":    ["notes", "note", "review", "comment", "comments", "my review",
                     "user review"],
        "hours":    ["hours", "hours played", "playtime", "time played",
                     "play time", "hours_played", "total hours"],
    ]

    /// RFC-4180-ish parser: handles quoted fields, embedded commas, escaped
    /// quotes, and CRLF. Written by hand because the alternative is a
    /// dependency for ~50 lines.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.startIndex

        while iterator < text.endIndex {
            let char = text[iterator]
            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")          // escaped quote
                        iterator = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",":  row.append(field); field = ""
                // NOTE: in Swift "\r\n" is a SINGLE Character (one grapheme
                // cluster), so a bare "\n" case silently misses every CRLF
                // file — i.e. most Windows and many app exports.
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    rows.append(row); row = []
                default:   field.append(char)
                }
            }
            iterator = text.index(after: iterator)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    static func parse(_ text: String) -> ParseResult {
        let grid = parseCSV(text)
        guard let header = grid.first else {
            return ParseResult(rows: [], recognizedColumns: [], ignoredColumns: [], skippedLines: [])
        }

        // A scale in the header is a note to the reader, not part of the
        // name: Gamery writes "User Rating (1-5)", which matched nothing and
        // was ignored while "user rating" sat in the aliases.
        let normalized = header.map {
            $0.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var indexFor: [String: Int] = [:]
        var recognized: [String] = []
        var ignored: [String] = []

        for (index, column) in normalized.enumerated() {
            if let field = aliases.first(where: { $0.value.contains(column) })?.key,
               indexFor[field] == nil {
                indexFor[field] = index
                recognized.append(header[index])
            } else {
                ignored.append(header[index])
            }
        }

        var rows: [Row] = []
        var skipped: [Int] = []
        for (offset, raw) in grid.dropFirst().enumerated() {
            let line = offset + 2   // 1-based, and the header is line 1
            func value(_ field: String) -> String? {
                guard let index = indexFor[field], index < raw.count else { return nil }
                let trimmed = raw[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard let name = value("name") else { skipped.append(line); continue }
            let platforms = CSVImport.splitPlatforms(value("platform"))
            rows.append(Row(
                name: name,
                platform: platforms.first,
                platforms: platforms,
                status: value("status").flatMap(status(from:)),
                rating: value("rating").flatMap(rating(from:)),
                notes: value("notes"),
                hoursPlayed: value("hours").flatMap(hours(from:)),
                igdbID: value("igdb").flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil },
                line: line
            ))
        }
        return ParseResult(rows: rows, recognizedColumns: recognized,
                           ignoredColumns: ignored, skippedLines: skipped)
    }

    // MARK: Value coercion

    /// Map another app's vocabulary onto our statuses. Unknown values fall
    /// back to backlog rather than dropping the row.
    static func status(from raw: String) -> GameStatus {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "playing", "in progress", "in-progress", "started", "now playing",
             "currently playing":                           .playing
        case "paused", "on hold", "on-hold", "hold":        .paused
        case "completed", "finished", "beaten", "complete",
             "100%", "mastered", "retired":                 .completed
        case "queued", "up next", "next", "planning",
             "plan to play", "want to play":                .queued
        case "shelved", "backlog?", "someday":              .shelved
        // Build 36. The words people actually use for it, including the ones
        // other trackers export.
        case "old favorite", "old favorite", "oldfavorite",
             "played to death", "childhood", "retro favorite":  .oldFavorite
        case "abandoned", "dropped", "quit", "unfinished":  .abandoned
        case "wishlist", "wish list", "wanted":             .wishlist
        default:                                            .backlog
        }
    }

    /// A platform cell split into its systems: `"Xbox,Mac"` is two.
    static func splitPlatforms(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var seen = Set<String>()
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// **Add the reviewed rows to the library, in ONE save.**
    ///
    /// Out of the view so it can be tested, and batched: `addGame` saves as it
    /// goes, which for a 140-row file was 140 saves on the main thread, each
    /// queuing its own iCloud export. The rows are inserted, then committed
    /// together.
    struct Applied: Equatable {
        /// Games new to the library.
        var added = 0
        /// Games you had, now owned on another console too.
        var updated = 0
    }

    @MainActor @discardableResult
    static func apply(_ picks: [(row: Row, match: IGDBGame?)], context: ModelContext,
                      sourceLabel: String = "CSV") -> Applied {
        let repo = Repository(context)
        var count = 0
        var updated = 0
        for (row, match) in picks {
            if let id = row.existingGameID {
                let found = try? context.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })).first
                if let found, addOwnedPlatforms(row.platforms, to: found) {
                    repo.touch(found)
                    updated += 1
                }
                continue
            }
            let game: Game
            if let match {
                game = repo.addGame(from: match, platform: row.platform,
                                    status: row.status ?? .backlog, saving: false)
            } else {
                game = repo.addGame(name: row.name, status: row.status ?? .backlog, saving: false)
                if !row.platforms.isEmpty { game.platforms = row.platforms }
            }
            // Owned on every system the row names, each first in the
            // availability list, in the row's order.
            if row.platforms.count > 1 {
                game.ownedPlatforms = row.platforms
                game.platforms = row.platforms + game.platforms.filter { !row.platforms.contains($0) }
            }
            if let cover = row.coverURL, (game.coverURLString ?? "").isEmpty {
                game.coverURLString = cover
            }
            game.rating = row.rating
            if let notes = row.notes { game.notes = notes }
            // Hours become one manual session, so the number shows up in
            // stats without inventing a fake play history.
            if let hours = row.hoursPlayed, hours > 0 {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logManualSession(on: pt, duration: hours * 3600,
                                      // Ending now, not starting now: dated at the
                                      // import, a 42-minute session ended in the future.
                                      date: .now.addingTimeInterval(-hours * 3600),
                                      notes: "Imported from \(sourceLabel)")
            }
            count += 1
        }
        BuiltinTrackers.installMissing(context: context)
        PersistenceMonitor.shared.commit(context)
        return Applied(added: count, updated: updated)
    }

    /// How a service import sees the library: games it can add a console to,
    /// by `TrackerMerge.matchKey` of the name and by IGDB id, and the
    /// wishlist it skips (nobody owns a game they're waiting for).
    struct LibraryKeys {
        var byName: [String: UUID] = [:]
        var byIGDB: [Int: UUID] = [:]
        var wishlistNames: Set<String> = []
        var wishlistIGDBIDs: Set<Int> = []

        init(_ games: [Game]) {
            for game in games {
                if game.status == .wishlist {
                    wishlistNames.insert(game.name.lowercased())
                    if let id = game.igdbID { wishlistIGDBIDs.insert(id) }
                } else {
                    byName[TrackerMerge.matchKey(game.name)] = byName[TrackerMerge.matchKey(game.name)] ?? game.id
                    if let id = game.igdbID { byIGDB[id] = byIGDB[id] ?? game.id }
                }
            }
        }
    }

    /// Rows worth reviewing: a game you have only gets one when the console
    /// it would start on isn't already one you own it on. Otherwise a second
    /// run of an import opens on a sheet of games with nothing to add.
    @MainActor
    static func dropNothingToAdd(_ rows: [Row], context: ModelContext) -> [Row] {
        let owned = Set(Repository(context).liveConsoles().map(\.platform))
        return rows.filter { row in
            guard let id = row.existingGameID else { return true }
            guard let game = try? context.fetch(
                FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })).first else { return false }
            let have = Set(game.ownedPlatformNames.map(PlatformKey.canonical))
            let start = row.offersPlatformChoice && !row.platformsKnown
                ? preferOwnedPlatform(row, choices: platformChoices(for: row, matchPlatforms: [], owned: owned),
                                      owned: owned).platforms
                : row.platforms
            return start.contains { !have.contains(PlatformKey.canonical($0)) }
        }
    }

    /// Own `game` on each of `platforms` as well, under any spelling. False
    /// when it already was.
    static func addOwnedPlatforms(_ platforms: [String], to game: Game) -> Bool {
        let current = game.ownedPlatformNames
        var keys = Set(current.map(PlatformKey.canonical))
        let added = platforms.filter { keys.insert(PlatformKey.canonical($0)).inserted }
        guard !added.isEmpty else { return false }
        game.ownedPlatforms = current + added
        for platform in added {
            let key = PlatformKey.canonical(platform)
            if !game.platforms.contains(where: { PlatformKey.canonical($0) == key }) {
                game.platforms.append(platform)
            }
        }
        return true
    }

    /// Accepts 1–5, 1–10, and percentages, normalizing to the app's 1–5.
    static func rating(from raw: String) -> Int? {
        // Some exports use literal stars rather than a number.
        let stars = raw.filter { $0 == "★" }.count
        if stars > 0, Double(raw.filter({ $0.isNumber || $0 == "." })) == nil {
            return min(5, stars)
        }
        let cleaned = raw.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "★", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        let scaled: Double
        switch value {
        case ...5:   scaled = value
        case ...10:  scaled = value / 2
        default:     scaled = value / 20      // out of 100
        }
        return min(5, max(1, Int(scaled.rounded())))
    }

    /// "12", "12.5", "12h", "12 hours", "1,234" → hours as a Double.
    static func hours(from raw: String) -> Double? {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "hours", with: "")
            .replacingOccurrences(of: "hrs", with: "")
            .replacingOccurrences(of: "h", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
