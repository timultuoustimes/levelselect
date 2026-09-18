import Foundation

/// A game coming out — on at least one platform — for News → Upcoming.
///
/// **Per platform, not per game.** The first version asked IGDB for games
/// whose `first_release_date` was ahead, which silently drops every port and
/// every late platform: LEGO Batman: Legacy of the Dark Knight came out in May
/// on PS5, Xbox and PC and reaches Switch 2 on 18 September, and it was
/// missing — along with the Kingdom Hearts collections on Switch 2 and Hell is
/// Us. Tim, 09-18, with Game Informer's list beside ours: *"There are a lot of
/// games missing from ours that are upcoming, and some really big ones too."*
/// So a release is every launch row IGDB lists, and the list asks "what comes
/// out next on the systems you care about".
struct UpcomingRelease: Identifiable, Hashable, Codable, Sendable {
    struct Row: Hashable, Codable, Sendable {
        /// `PlatformKey.canonical` — "Switch 2", "PS5", "PC".
        let platform: String
        let date: Date
        let precision: IGDBGame.ReleasePrecision
    }

    let id: Int
    let name: String
    let slug: String?
    let coverImageID: String?
    let summary: String?
    let genres: [String]
    let developers: [String]
    let publishers: [String]
    let videoIDs: [String]
    /// Every launch IGDB lists, one per platform (its earliest launch there).
    let rows: [Row]

    init(id: Int, name: String, slug: String? = nil, coverImageID: String? = nil, summary: String? = nil,
         genres: [String] = [], developers: [String] = [], publishers: [String] = [],
         videoIDs: [String] = [], rows: [Row]) {
        self.id = id; self.name = name; self.slug = slug; self.coverImageID = coverImageID
        self.summary = summary; self.genres = genres; self.developers = developers
        self.publishers = publishers; self.videoIDs = videoIDs; self.rows = rows
    }

    init?(_ game: IGDBGame) {
        var earliest: [String: Row] = [:]
        for r in game.launchReleases {
            let p = PlatformKey.canonical(r.platform)
            let row = Row(platform: p, date: Date(timeIntervalSince1970: r.timestamp), precision: r.precision)
            if let have = earliest[p], have.date <= row.date { continue }
            earliest[p] = row
        }
        guard !earliest.isEmpty else { return nil }
        self.init(id: game.id, name: game.name, slug: game.slug, coverImageID: game.coverImageID,
                  summary: game.summary, genres: game.genres, developers: game.developers,
                  publishers: game.publishers, videoIDs: game.videoIDs,
                  rows: earliest.values.sorted { ($0.date, $0.platform) < ($1.date, $1.platform) })
    }

    var coverURL: URL? {
        coverImageID.flatMap { URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\($0).jpg") }
    }

    /// The next launch on the platforms you allow: its date, how precise that
    /// date is, and every allowed platform launching that same day.
    struct Next: Hashable, Sendable {
        let date: Date
        let precision: IGDBGame.ReleasePrecision
        let platforms: [String]
    }

    func next(on allowed: Set<String>, from start: Date) -> Next? {
        let ahead = rows.filter { allowed.contains($0.platform) && $0.date >= start }
        guard let first = ahead.min(by: { $0.date < $1.date }) else { return nil }
        let same = ahead.filter { UpcomingReleases.utc.isDate($0.date, inSameDayAs: first.date) }
        return Next(date: first.date, precision: first.precision, platforms: same.map(\.platform))
    }

    /// Its latest launch in `[since, before)` on the platforms you allow —
    /// for Just Out. Only exact days: "sometime this month" isn't news.
    func recent(on allowed: Set<String>, since: Date, before: Date) -> Next? {
        let past = rows.filter { allowed.contains($0.platform) && $0.precision.hasDay
                                 && $0.date >= since && $0.date < before }
        guard let last = past.max(by: { $0.date < $1.date }) else { return nil }
        let same = past.filter { UpcomingReleases.utc.isDate($0.date, inSameDayAs: last.date) }
        return Next(date: last.date, precision: last.precision, platforms: same.map(\.platform))
    }

    /// Platforms it is already out on — "Out on PS5 · PC since 22 May".
    func alreadyOut(before start: Date) -> [Row] {
        rows.filter { $0.date < start && $0.precision.hasDay }
    }
}

enum UpcomingReleases {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// The systems a list shows when nobody has chosen: the current big
    /// consoles, PC and Mac. Mobile and VR are left to the ones you own —
    /// a month of App Store releases would bury everything else.
    static let mainPlatforms: Set<String> = ["PS5", "PS4", "Xbox Series", "Xbox One", "Switch", "Switch 2", "PC", "Mac"]

    /// Everything you can pick in the systems sheet, most common first.
    static let pickable: [String] = ["Switch 2", "Switch", "PS5", "PS4", "Xbox Series", "Xbox One",
                                     "PC", "Mac", "iOS", "Android", "Steam Deck"]

    /// How far back New & Upcoming looks. Tim suggested a week, to catch
    /// *"a new game someone might have missed otherwise"*; two, because games
    /// launch Tuesday to Friday and a week drops last Thursday's by this
    /// Thursday — the one someone checking weekly would miss.
    static let justOutDays = 14

    /// Games out in the last `justOutDays`, newest first.
    static func justOut(_ releases: [UpcomingRelease], allowed: Set<String>,
                        today start: Date) -> [(release: UpcomingRelease, next: UpcomingRelease.Next)] {
        let since = start.addingTimeInterval(-Double(justOutDays) * 86_400)
        return releases.compactMap { r in r.recent(on: allowed, since: since, before: start).map { (r, $0) } }
            .sorted { ($0.1.date, $1.0.name) > ($1.1.date, $0.0.name) }
            .map { (release: $0.0, next: $0.1) }
    }

    /// One month's section, or the "sometime later" pile.
    struct Section: Identifiable, Hashable {
        /// First of the month, or nil for the dates that aren't a day or month.
        let month: Date?
        let items: [(release: UpcomingRelease, next: UpcomingRelease.Next)]
        var id: String { month.map { "\($0.timeIntervalSince1970)" } ?? "later" }

        static func == (a: Section, b: Section) -> Bool { a.id == b.id && a.items.count == b.items.count }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    /// Month sections for day- and month-precise dates, then everything IGDB
    /// only knows by quarter or year. **Why the split:** IGDB pads "2026" to 31
    /// December, and measured on 09-18 that put 699 games in "December 2026"
    /// against 46 in November.
    static func sections(_ releases: [UpcomingRelease], allowed: Set<String>, from start: Date) -> [Section] {
        var byMonth: [Date: [(UpcomingRelease, UpcomingRelease.Next)]] = [:]
        var later: [(UpcomingRelease, UpcomingRelease.Next)] = []
        for r in releases {
            guard let n = r.next(on: allowed, from: start) else { continue }
            if n.precision == .day || n.precision == .month {
                let m = utc.date(from: utc.dateComponents([.year, .month], from: n.date)) ?? n.date
                byMonth[m, default: []].append((r, n))
            } else {
                later.append((r, n))
            }
        }
        func order(_ list: [(UpcomingRelease, UpcomingRelease.Next)]) -> [(release: UpcomingRelease, next: UpcomingRelease.Next)] {
            list.sorted { a, b in
                // A month-only date sorts after that month's dated games.
                let ad = (a.1.precision == .day ? 0 : 1, a.1.date, a.0.name)
                let bd = (b.1.precision == .day ? 0 : 1, b.1.date, b.0.name)
                return ad < bd
            }.map { (release: $0.0, next: $0.1) }
        }
        var out = byMonth.keys.sorted().map { Section(month: $0, items: order(byMonth[$0]!)) }
        if !later.isEmpty { out.append(Section(month: nil, items: order(later))) }
        return out
    }
}
