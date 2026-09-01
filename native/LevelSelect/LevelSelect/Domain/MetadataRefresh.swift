import Foundation

/// Filling in what the library never knew.
///
/// Tim's library arrived from a CSV in the web-app era, and it arrived thin.
/// 119 of its 164 games carry a `firstReleaseDate` of timestamp zero, which
/// draws as 1969 on the game page and once put a hundred-game bar on the Stats
/// year chart. The same rows are missing genres, developers, covers. The games
/// already carry `igdbID`, so the facts are one lookup away — this is a
/// refresh, not a re-match.
///
/// **Additive only, and that is the whole design.** A field that already holds
/// something is never written. Tim is hand-correcting this library right now —
/// platform names, the handful of games carrying IGDB's vocabulary instead of
/// his — and a refresh that overwrote non-empty fields would silently undo
/// exactly the corrections it exists to make unnecessary. The feature and the
/// hazard arrive together, so the answer is to build the half that cannot
/// destroy anything.
///
/// The overwriting half needs per-field locks (a padlock per field, Plex-style)
/// to be safe, and locks need a stored property on `Game`, which is Schema V3
/// and held with the rest of that batch. See
/// `Backlog/LevelSelect metadata editing, matching and labels 2026-08-23`.
/// Nothing here should be relaxed into an overwrite before those land.
enum MetadataRefresh {

    // MARK: What counts as empty

    /// A date this close to the Unix epoch is an import artifact, not a launch
    /// window. The web-app CSV path wrote a missing release date as timestamp
    /// zero, and no real library has a hundred games from the year before Pong.
    ///
    /// Two days rather than zero because the same row could land either side of
    /// the epoch once a timezone is applied to it.
    static let epochArtifactWindow: TimeInterval = 172_800

    /// IGDB year-only precision lands on **1 January**, so a date that falls
    /// there almost certainly means "sometime that year" rather than New
    /// Year's Day. Lives here because date precision is this type's business;
    /// `WishlistShelf` reads it to decide what it can honestly print.
    /// See `ReleaseCountdown.isYearOnly` — the rule lives in Shared now, so
    /// the widget extension applies exactly the same one.
    static func isYearOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        ReleaseCountdown.isYearOnly(date)
    }

    /// A year-only date for the current year or later is **upgradeable**: the
    /// game is coming and nobody has announced a day yet, so IGDB may know one
    /// tomorrow even though the field is not empty.
    ///
    /// The one deliberate exception to additive-only, and it is narrow on
    /// purpose. Release dates are fetched, never typed — nothing the user
    /// wrote can be sitting in the field — and replacing "1 January 2026" with
    /// "12 November 2026" is strictly better information about the same event.
    /// Past years are excluded: most of the retro library is year-only and
    /// none of it is going to be announced.
    static func awaitsAnnouncedDate(_ date: Date?, now: Date = .now,
                                    calendar: Calendar = .current) -> Bool {
        guard let date, !isMissing(date), isYearOnly(date) else { return false }
        return calendar.component(.year, from: date) >= calendar.component(.year, from: now)
    }

    /// Is this release date absent — either genuinely nil, or the epoch
    /// placeholder that renders as 1969?
    ///
    /// The single definition of that question; Stats and the fill pass both
    /// read it, so a game hidden from the year chart is exactly a game this
    /// pass will try to fix.
    static func isMissing(_ date: Date?) -> Bool {
        guard let date else { return true }
        return abs(date.timeIntervalSince1970) < epochArtifactWindow
    }

    /// IGDB summaries the web app stored were capped at 200 characters, so a
    /// summary of exactly that length is a truncation artifact rather than a
    /// value. `GameDetailView` already heals these one game at a time on open;
    /// this is the same rule applied to the whole library at once.
    ///
    /// Safe to treat as empty because `summary` is display-only — it is
    /// fetched, never typed. Nothing the user wrote can be sitting in it.
    static func isMissing(summary: String?) -> Bool {
        guard let summary, !summary.isEmpty else { return true }
        return summary.count == 200
    }

    // MARK: Fields

    /// The fields this pass will fill. Deliberately a closed list.
    ///
    /// Absent by design:
    ///
    /// - `name` — the user's, and never empty anyway.
    /// - ~~`platforms`~~ — **admitted 2026-08-31.** It was excluded because
    ///   writing IGDB's full list into a game that says "Switch" would
    ///   reintroduce the vocabulary split, and because position zero is the
    ///   ownership record. Both are handled now: the write is a MERGE that
    ///   keeps position zero and dedupes by `PlatformIcon.consoleKey`, so one
    ///   console cannot appear twice under two spellings and the platform you
    ///   own is never moved. The field still conflates "released on" with "I
    ///   own it on" — that split is the V3 `ownedPlatforms` item — but filling
    ///   the availability half does not make the conflation worse.
    ///
    ///   Worth doing because of who has the gap: games added through IGDB
    ///   search already arrive with the full list (`addGame(from:platform:)`
    ///   stores `[chosen] + igdb.platforms`). Only the CSV and legacy-import
    ///   paths write a single entry — which is Tim's library, and almost
    ///   nobody else's.
    /// - status, rating, review, notes, ownership, tags — user data. A
    ///   metadata refresh has no business anywhere near them.
    enum Field: String, CaseIterable, Sendable {
        case releaseDate
        case cover
        case genres
        case themes
        case gameModes
        case playerPerspectives
        case developers
        case publishers
        case franchise
        case summary
        case slug
        case platforms

        /// Plural, for "119 games are missing a release date".
        var label: String {
            switch self {
            case .releaseDate:        "a release date"
            case .cover:              "cover art"
            case .genres:             "genres"
            case .themes:             "themes"
            case .gameModes:          "game modes"
            case .playerPerspectives: "a perspective"
            case .developers:         "a developer"
            case .publishers:         "a publisher"
            case .franchise:          "a series"
            case .summary:            "a description"
            case .slug:               "an IGDB link"
            case .platforms:          "a platform list nobody has checked"
            }
        }

        /// The bare noun, for the informational rows — "No series listed",
        /// where the articled `label` produced "No a series listed".
        var bareLabel: String {
            switch self {
            case .releaseDate:        "release date"
            case .cover:              "cover art"
            case .genres:             "genres"
            case .themes:             "themes"
            case .gameModes:          "game modes"
            case .playerPerspectives: "perspective"
            case .developers:         "developer"
            case .publishers:         "publisher"
            case .franchise:          "series"
            case .summary:            "description"
            case .slug:               "IGDB link"
            case .platforms:          "platform list"
            }
        }

        /// Report order — most visible problem first. The 1969 dates are the
        /// reason this exists, so they lead.
        static let reportOrder: [Field] = [
            .releaseDate, .cover, .platforms, .genres, .developers, .publishers,
            .themes, .gameModes, .playerPerspectives, .franchise, .summary, .slug,
        ]
    }

    /// Availability from IGDB, ownership from the user, neither overwriting
    /// the other.
    ///
    /// - **Position zero is preserved.** It is the record of a choice, and
    ///   every label, grouping and filter in the app reads it as "the one you
    ///   own". Nothing here may move it.
    /// - The user's spelling wins on collision. Someone who stored "PC" must
    ///   not end up with both "PC" and "PC (Microsoft Windows)" — two rows for
    ///   one console is the exact bug `PlatformShort` exists to prevent.
    ///   Sameness is `PlatformIcon.consoleKey`: the artwork IS the identity.
    /// - Hand-added platforms IGDB has never heard of survive. Emulation and
    ///   unlisted ports are real, and a refresh that silently deleted them
    ///   would punish the people most likely to run it.
    static func mergedPlatforms(existing: [String], igdb: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for platform in existing + igdb
        where seen.insert(PlatformIcon.consoleKey(platform)).inserted {
            out.append(platform)
        }
        return out
    }

    /// Which of the fillable fields this game currently has nothing in.
    static func missingFields(of game: Game) -> Set<Field> {
        var missing: Set<Field> = []
        if isMissing(game.firstReleaseDate) || awaitsAnnouncedDate(game.firstReleaseDate) {
            missing.insert(.releaseDate)
        }
        if (game.coverImageID ?? "").isEmpty && (game.coverURLString ?? "").isEmpty {
            missing.insert(.cover)
        }
        if game.genres.isEmpty { missing.insert(.genres) }
        if game.themes.isEmpty { missing.insert(.themes) }
        if game.gameModes.isEmpty { missing.insert(.gameModes) }
        if game.playerPerspectives.isEmpty { missing.insert(.playerPerspectives) }
        if game.developers.isEmpty { missing.insert(.developers) }
        if game.publishers.isEmpty { missing.insert(.publishers) }
        if (game.franchise ?? "").isEmpty { missing.insert(.franchise) }
        if isMissing(summary: game.summary) { missing.insert(.summary) }
        // Platforms are deliberately NOT decided here — see `plan`.
        //
        // No count means "complete": only IGDB knows how many platforms a game
        // shipped on, so any threshold is a guess about someone else's data.
        // This used to read `count <= 1`, on the theory that one entry meant
        // "never merged". Ball x Pit had TWO — Switch and iOS — so the pass
        // skipped it and truthfully reported nothing to update, while a
        // per-game Refresh immediately added more.
        //
        // Making it always-missing was worse: a library could then never be
        // complete, and the pass would re-ask every game forever. The question
        // is not "is this list short" but "has anyone ever asked", which is a
        // fact about the RUN rather than the game, and `plan` holds it.
        return missing
    }

    // MARK: Planning a run

    /// What a run would do, worked out before anything is asked of the network.
    struct Plan {
        /// Games with an `igdbID` and at least one empty field — the work.
        var fillable: [Game] = []
        /// Games missing something but with no `igdbID` to look up. Counted and
        /// reported, never guessed at: matching these by name is the CSV
        /// importer's review flow, and silently picking a title is how "The
        /// Messenger" became a different game from 2000.
        var unmatched: [Game] = []
        /// Games with nothing missing.
        var complete: Int = 0
        /// Games whose only absences are informational (no series) — reported,
        /// never offered as work.
        var informationalOnly: Int = 0
        /// Games IGDB was asked about recently and had nothing to add for —
        /// excluded from `fillable` until the answer goes stale.
        var recentlyChecked: Int = 0
        /// How many games lack each field, across the whole library.
        var missingCounts: [Field: Int] = [:]
        /// Games in `fillable` whose ONLY reason to be looked up is a platform
        /// list too short to trust. They appear in no `missingCounts` row, so
        /// the report has to name them separately or they are unexplained.
        var platformOnly: Int = 0

        var isEmpty: Bool { fillable.isEmpty }

        /// Field counts in report order, dropping the ones nothing is missing
        /// and the informational ones — those get their own line, phrased as
        /// a fact rather than a gap.
        var reportableCounts: [(Field, Int)] {
            Field.reportOrder.compactMap { field in
                guard !MetadataRefresh.informational.contains(field) else { return nil }
                return (missingCounts[field] ?? 0) > 0 ? (field, missingCounts[field]!) : nil
            }
        }

        /// The informational counts ("69 have no series listed"), for the
        /// report's footnote row.
        var informationalCounts: [(Field, Int)] {
            Field.reportOrder.compactMap { field in
                guard MetadataRefresh.informational.contains(field) else { return nil }
                return (missingCounts[field] ?? 0) > 0 ? (field, missingCounts[field]!) : nil
            }
        }
    }

    /// Fields whose absence is usually a fact about the game, not a gap in
    /// the data — most games simply aren't in a series. They still FILL when a
    /// game is looked up for other reasons, and they still report, but they
    /// never make a game "fillable" on their own: 69 series-less games
    /// permanently demanding a lookup was the sheet crying wolf.
    static let informational: Set<Field> = [.franchise]

    /// A cheap "this list did not come from an importer" test, used only to
    /// keep the FIRST pass over a fresh library from looking up every game
    /// that obviously already has IGDB's answer. Deliberately generous: a
    /// wrong guess here costs one lookup, which the run then remembers.
    static func hasBeenAskedAbout(_ game: Game) -> Bool {
        game.platforms.count >= 3
    }

    /// How long "IGDB had nothing to add" stays believed before a game is
    /// worth asking about again. Upstream data does grow — a month is long
    /// enough to stop the sheet re-offering the same dead lookups every run,
    /// short enough that new IGDB data eventually arrives on its own.
    static let recheckAfter: TimeInterval = 30 * 24 * 3600

    /// Sort a library into work, unmatchable, and already-complete.
    ///
    /// Deleted games are skipped — deletion is soft here, and a refresh has no
    /// reason to spend a lookup on a row that is on its way out.
    ///
    /// `checked` is the asked-and-answered cache: game id → when a lookup last
    /// came back with nothing to add. Those games stay *missing* (the report
    /// still counts them) but stop being *work* until the answer goes stale —
    /// the difference between "no data locally" and "no data anywhere".
    static func plan(for library: [Game],
                     checked: [UUID: Date] = [:],
                     now: Date = .now) -> Plan {
        var plan = Plan()
        for game in library where game.deletedAt == nil {
            let missing = missingFields(of: game)
            guard !missing.isEmpty else {
                plan.complete += 1
                continue
            }
            for field in missing { plan.missingCounts[field, default: 0] += 1 }
            // Informational absences report but never demand a lookup.
            guard !missing.subtracting(informational).isEmpty else {
                plan.informationalOnly += 1
                continue
            }
            if let asked = checked[game.id], now.timeIntervalSince(asked) < recheckAfter {
                plan.recentlyChecked += 1
                continue
            }
            if game.igdbID != nil {
                plan.fillable.append(game)
            } else {
                plan.unmatched.append(game)
            }
        }

        // A game nothing is missing from is still worth ONE lookup if IGDB has
        // never been asked about it, because its platform list may be a
        // fragment nobody can measure — see `missingFields`. Bounded, and it
        // converges: the run marks every game it learns nothing new from, so
        // the second pass over a library reports it complete and makes no
        // requests at all.
        for game in library where game.deletedAt == nil
        && game.igdbID != nil && checked[game.id] == nil {
            guard !plan.fillable.contains(where: { $0.id == game.id }) else { continue }
            guard !MetadataRefresh.hasBeenAskedAbout(game) else { continue }
            plan.complete = max(0, plan.complete - 1)
            plan.platformOnly += 1
            plan.fillable.append(game)
        }
        return plan
    }

    // MARK: Applying

    /// Write IGDB's answer into the empty fields of one game.
    ///
    /// Returns what it actually filled, which is how the run reports a real
    /// number rather than "done". A field IGDB has nothing for stays empty and
    /// is not counted — nothing writes an empty string over an empty string.
    ///
    /// Every branch here is `isEmpty` on the game side first. That ordering is
    /// the guarantee; keep it that way.
    @discardableResult
    static func fill(_ game: Game, from igdb: IGDBGame) -> Set<Field> {
        var filled: Set<Field> = []

        if isMissing(game.firstReleaseDate),
           let date = igdb.storableReleaseDate(on: game.primaryOwnedPlatform) {
            game.firstReleaseDate = date
            filled.insert(.releaseDate)
        } else if awaitsAnnouncedDate(game.firstReleaseDate),
                  let date = igdb.storableReleaseDate(on: game.primaryOwnedPlatform),
                  !isYearOnly(date),
                  Calendar.current.component(.year, from: date)
                    == Calendar.current.component(.year, from: game.firstReleaseDate!) {
            // The day got announced. Same year only, so a fuzzy answer can
            // never quietly move a game into a different one.
            game.firstReleaseDate = date
            filled.insert(.releaseDate)
        }
        if (game.coverImageID ?? "").isEmpty && (game.coverURLString ?? "").isEmpty,
           let cover = igdb.coverImageID, !cover.isEmpty {
            game.coverImageID = cover
            game.coverURLString = igdb.coverURLString
            filled.insert(.cover)
        }
        if game.genres.isEmpty, !igdb.genres.isEmpty {
            game.genres = igdb.genres
            filled.insert(.genres)
        }
        if game.themes.isEmpty, !igdb.themes.isEmpty {
            game.themes = igdb.themes
            filled.insert(.themes)
        }
        if game.gameModes.isEmpty, !igdb.gameModes.isEmpty {
            game.gameModes = igdb.gameModes
            filled.insert(.gameModes)
        }
        if game.playerPerspectives.isEmpty, !igdb.playerPerspectives.isEmpty {
            game.playerPerspectives = igdb.playerPerspectives
            filled.insert(.playerPerspectives)
        }
        if game.developers.isEmpty, !igdb.developers.isEmpty {
            game.developers = igdb.developers
            filled.insert(.developers)
        }
        if game.publishers.isEmpty, !igdb.publishers.isEmpty {
            game.publishers = igdb.publishers
            filled.insert(.publishers)
        }
        if (game.franchise ?? "").isEmpty, let franchise = igdb.franchise, !franchise.isEmpty {
            game.franchise = franchise
            filled.insert(.franchise)
        }
        if isMissing(summary: game.summary), let summary = igdb.summary, !summary.isEmpty {
            game.summary = summary
            filled.insert(.summary)
        }
        // Same reasoning as `missingFields`: merge whenever IGDB has anything,
        // and let the "did it actually grow" check below decide whether that
        // counted as filling a field.
        if !igdb.platforms.isEmpty {
            let merged = mergedPlatforms(existing: game.platforms, igdb: igdb.platforms)
            // Only a real gain counts. A one-platform exclusive merges to
            // itself, and reporting that as a filled field would make the
            // pass claim work it did not do.
            if merged.count > game.platforms.count {
                game.platforms = merged
                filled.insert(.platforms)
            }
        }
        if (game.igdbSlug ?? "").isEmpty, let slug = igdb.slug, !slug.isEmpty {
            game.igdbSlug = slug
            filled.insert(.slug)
        }

        return filled
    }

    // MARK: Fix Match

    /// Re-point a game at a different IGDB entry and replace its fetched
    /// layer wholesale.
    ///
    /// This is the one deliberate exception to additive-only, and it's safe
    /// for exactly the reason the fill is: the boundary between fetched and
    /// typed is a field list, not a guess. Everything `fill` manages came
    /// from the OLD match, so after a rematch it describes the wrong game —
    /// keeping it would be the corruption. Everything the user owns — the
    /// name they may have set, platforms, rating, notes, review, tags,
    /// status, ownership, playthroughs — is untouched.
    ///
    /// Absent values CLEAR the field rather than surviving: a wrong game's
    /// summary is worse than no summary.
    static func rematch(_ game: Game, to igdb: IGDBGame) {
        game.igdbID = igdb.id
        game.igdbSlug = igdb.slug
        game.firstReleaseDate = igdb.releaseDate
        game.coverImageID = igdb.coverImageID
        game.coverURLString = igdb.coverURLString
        game.genres = igdb.genres
        game.themes = igdb.themes
        game.gameModes = igdb.gameModes
        game.playerPerspectives = igdb.playerPerspectives
        game.developers = igdb.developers
        game.publishers = igdb.publishers
        game.franchise = igdb.franchise
        game.summary = igdb.summary
    }

    // MARK: Spending the proxy's quota

    /// How much of the IGDB proxy's allowance one run is willing to spend.
    ///
    /// The proxy (`supabase/functions/igdb-proxy`) guards on three buckets:
    /// 60 requests per minute per install, 2,000 per day per install, and
    /// 20,000 per day across everyone. Tracker generation runs on a separate
    /// function with its own bucket, so a refresh cannot starve it — but a
    /// per-game loop would still have cost 164 requests to fix 164 games, or
    /// nearly three minutes of the per-minute allowance.
    ///
    /// It does not have to. IGDB matches a list — `where id = (1,2,3)` — so a
    /// whole library fits in a handful of requests. At 50 per chunk, 164 games
    /// costs four, which is 0.2% of the day's per-install budget.
    enum Budget {
        /// Ids per request. Bounded by the proxy's 2,000-character query cap
        /// (`MAX_QUERY_LENGTH`) and 4,000-byte body cap, not by IGDB: the field
        /// list is ~450 characters and 50 ids add ~350 more, leaving the query
        /// at roughly 40% of the limit even for seven-digit ids.
        static let chunkSize = 50

        /// Requests one run will make before stopping and reporting what is
        /// left. Twenty chunks is a thousand games — far past any real library
        /// — while spending a third of one minute's allowance, so a refresh
        /// never trips the rate limit and never leaves the app unable to search
        /// for the next thing the user adds.
        static let maxChunksPerRun = 20

        /// Games one run can cover.
        static var maxGamesPerRun: Int { chunkSize * maxChunksPerRun }

        /// A breath between chunks. Not required by the quota at this volume —
        /// it keeps a burst from looking like a scraper to the proxy's logs,
        /// and gives the progress bar something to animate against.
        static let pauseBetweenChunks: Duration = .milliseconds(300)
    }

    /// Split ids into request-sized chunks, in a stable order.
    ///
    /// Sorted and de-duplicated because a library can hold two rows pointing at
    /// the same IGDB id (sync duplicates, or the same game on two platforms),
    /// and paying twice for one answer is the one thing a quota-bounded pass
    /// should not do.
    static func chunks(of ids: [Int], size: Int = Budget.chunkSize) -> [[Int]] {
        precondition(size > 0, "chunk size must be positive")
        let unique = Array(Set(ids)).sorted()
        return stride(from: 0, to: unique.count, by: size).map {
            Array(unique[$0 ..< min($0 + size, unique.count)])
        }
    }

    /// The chunks a run will actually make, capped at the per-run budget.
    /// Anything past the cap is left for the next run — the pass is
    /// resumable because a filled game stops being fillable.
    static func scheduledChunks(of ids: [Int]) -> (run: [[Int]], deferred: Int) {
        let all = chunks(of: ids)
        guard all.count > Budget.maxChunksPerRun else { return (all, 0) }
        let run = Array(all.prefix(Budget.maxChunksPerRun))
        let deferred = all.dropFirst(Budget.maxChunksPerRun).reduce(0) { $0 + $1.count }
        return (run, deferred)
    }
}


/// The asked-and-answered cache: game id → when IGDB last had nothing to add.
///
/// Device-local UserDefaults on purpose. This is a cache of an upstream fact,
/// not user data — syncing it would spread one device's stale answer to
/// another, and re-asking per device costs one lookup a month.
struct MetadataCheckedStore {
    private static let key = "metadataFillCheckedAt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func all() -> [UUID: Date] {
        guard let raw = defaults.dictionary(forKey: Self.key) as? [String: Date] else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, date in
            UUID(uuidString: key).map { ($0, date) }
        })
    }

    func markChecked(_ ids: [UUID], at date: Date = .now) {
        guard !ids.isEmpty else { return }
        var raw = (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
        for id in ids { raw[id.uuidString] = date }
        defaults.set(raw, forKey: Self.key)
    }

    /// A field DID fill — the game is live upstream again, forget the "nothing
    /// there" answer so future absences re-ask promptly.
    func clear(_ id: UUID) {
        var raw = (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
        raw.removeValue(forKey: id.uuidString)
        defaults.set(raw, forKey: Self.key)
    }
}
