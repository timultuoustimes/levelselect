import Foundation

/// What a story is about, for the Topics rails and for ranking For You.
///
/// Matched from the headline and the feed's own category tags — never the
/// summary, where "also coming to PS5, Xbox and PC" would put every
/// multiplatform story in every rail. A feed from the catalog also lends its
/// group: a Push Square story is a PlayStation story whatever its headline.
enum NewsTopic: String, CaseIterable, Identifiable, Codable, Sendable {
    case reviews, nintendo, playstation, xbox, pc, mac, retro, previews, deals, indie
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reviews: "Reviews"
        case .nintendo: "Nintendo"
        case .playstation: "PlayStation"
        case .xbox: "Xbox"
        case .pc: "PC & Steam"
        case .mac: "Mac"
        case .retro: "Retro"
        case .previews: "Previews"
        case .deals: "Deals"
        case .indie: "Indie"
        }
    }

    /// Lowercased terms, matched on word boundaries. A trailing `*` matches
    /// as a prefix ("emulat*" for emulator and emulation).
    var terms: [String] {
        switch self {
        case .reviews: ["review", "reviews", "review in progress"]
        case .previews: ["preview", "previews", "hands-on", "hands on", "first look", "impressions"]
        case .nintendo: ["nintendo", "switch 2", "nintendo switch", "switch online", "mario", "zelda",
                         "pokémon", "pokemon", "metroid", "kirby", "splatoon", "donkey kong", "animal crossing"]
        case .playstation: ["playstation", "ps5", "ps4", "ps plus", "psvr2", "state of play", "dualsense"]
        case .xbox: ["xbox", "game pass", "series x", "series s"]
        case .pc: ["pc", "steam", "steam deck", "gog", "epic games store", "proton", "windows"]
        // No live Mac gaming site publishes a feed (checked 2026-09-17), so
        // Mac is gathered from everyone else's stories.
        case .mac: ["mac", "macos", "macbook", "apple silicon", "crossover", "game porting toolkit",
                    "apple arcade", "mac port", "on mac"]
        case .retro: ["retro", "snes", "super nintendo", "mega drive", "genesis", "dreamcast", "saturn",
                      "n64", "nintendo 64", "game boy", "gamecube", "ps1", "ps2", "famicom", "neo geo",
                      "pc engine", "turbografx", "atari", "commodore", "amiga", "emulat*", "remaster*",
                      "anniversary collection"]
        case .deals: ["deal", "deals", "sale", "discount", "% off", "price drop", "cheapest", "free games"]
        case .indie: ["indie", "indies", "itch.io", "indie world", "day of the devs"]
        }
    }

    func matches(_ story: FeedStory, group: FeedCatalog.Group?) -> Bool {
        if let group, group.topic == self { return true }
        // A review is a kind of article, not a word: "…Leave a Flood of
        // Negative Reviews" is news about a shop. So these two match the
        // headline SHAPES sites use, or the site's own category tag.
        if self == .reviews || self == .previews {
            return Self.isKind(self == .reviews ? "review" : "preview", story)
                || (self == .previews && terms.dropFirst(2).contains {
                    NewsMatch.contains(NewsMatch.fold(story.title), term: $0) })
        }
        let haystack = NewsMatch.fold(story.title + " | " + story.categories.joined(separator: " | "))
        return terms.contains { NewsMatch.contains(haystack, term: $0) }
    }

    /// "Hades II review", "Review: Hades II", "Silksong review – …",
    /// "Review in progress", or a category tag of Review(s).
    static func isKind(_ word: String, _ story: FeedStory) -> Bool {
        if story.categories.contains(where: { NewsMatch.fold($0).hasPrefix(word) }) { return true }
        let t = NewsMatch.fold(story.title).trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(" \(word)") || t.hasPrefix("\(word):") || t.hasPrefix("\(word) -") { return true }
        for tail in [":", " -", " –", " —", " |", " in progress", " roundup"] where t.contains(" \(word)\(tail)") {
            return true
        }
        return t.contains("mini \(word)")
    }

    /// Topics for the consoles you hold: owning a Switch puts Nintendo ahead
    /// of Xbox in the rails and in For You.
    static func owned(platforms: [String]) -> Set<NewsTopic> {
        var out: Set<NewsTopic> = []
        let current: Set<String> = ["switch", "switch 2", "ps5", "ps4", "xbox series", "xbox one",
                                    "pc", "mac", "steam deck", "ios", "android", "iphone", "ipad"]
        let nintendo: Set<String> = ["ds", "3ds", "gba", "gbc", "game boy", "nes", "snes", "n64", "gamecube",
                                     "famicom", "famicom disk system", "super famicom", "virtual boy"]
        for raw in platforms {
            let p = PlatformKey.canonical(raw).lowercased()
            if p.isEmpty || p == "other" { continue }
            if nintendo.contains(p) || p.contains("switch") || p.contains("nintendo") || p.contains("wii") {
                out.insert(.nintendo)
            }
            if p.hasPrefix("ps") || p.contains("playstation") || p == "vita" { out.insert(.playstation) }
            if p.contains("xbox") { out.insert(.xbox) }
            if p == "pc" || p.contains("steam") { out.insert(.pc) }
            if p.contains("mac") { out.insert(.mac) }
            if !current.contains(p) { out.insert(.retro) }
        }
        return out
    }

    /// Rail order: reviews first (everyone reads them), then your systems,
    /// then everything else in the declared order.
    static func ordered(owned: Set<NewsTopic>) -> [NewsTopic] {
        let rest = allCases.filter { $0 != .reviews }
        return [.reviews] + rest.filter(owned.contains) + rest.filter { !owned.contains($0) }
    }
}

/// Text matching shared by topics and games.
enum NewsMatch {
    /// Lowercased, accents folded, curly quotes straightened.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

    /// Whole-word containment. `term` is already folded; a trailing `*`
    /// makes it a prefix.
    static func contains(_ haystack: String, term: String) -> Bool {
        let prefix = term.hasSuffix("*")
        let word = NewsMatch.fold(prefix ? String(term.dropLast()) : term)
        var searchStart = haystack.startIndex
        while let r = haystack.range(of: word, range: searchStart..<haystack.endIndex) {
            let beforeOK = r.lowerBound == haystack.startIndex
                || !isWordChar(haystack[haystack.index(before: r.lowerBound)])
            let afterOK = prefix || r.upperBound == haystack.endIndex || !isWordChar(haystack[r.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = haystack.index(after: r.lowerBound)
        }
        return false
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }
}

/// Which of your games a headline is about.
///
/// A name matches whole, or by its subtitle when that is distinctive —
/// "Silksong" is how every headline says "Hollow Knight: Silksong". One-word
/// names must match with their capital, since "Control" and "Journey" are also
/// words; they will still catch the odd sentence that starts with one, which
/// costs a story in the wrong section, never a missing one.
struct GameNewsMatcher: Sendable {
    struct Target: Sendable, Hashable {
        let gameID: UUID
        let name: String
        let statusRaw: String
        let patterns: [String]
        let caseSensitive: [String]
    }

    let targets: [Target]

    init(games: [(id: UUID, name: String, statusRaw: String)]) {
        var out: [Target] = []
        for g in games {
            let (folded, exact) = Self.patterns(for: g.name)
            if folded.isEmpty && exact.isEmpty { continue }
            out.append(Target(gameID: g.id, name: g.name, statusRaw: g.statusRaw,
                              patterns: folded, caseSensitive: exact))
        }
        targets = out
    }

    /// Words that make a subtitle too generic to stand for the game.
    private static let generic: Set<String> = [
        "remastered", "remake", "definitive edition", "complete edition", "deluxe edition",
        "game of the year edition", "goty edition", "the game", "hd", "director's cut",
        "anniversary edition", "special edition", "enhanced edition", "reloaded", "origins",
        "legacy", "chronicles", "collection", "returns", "reborn", "the beginning", "episode 1"]

    static func patterns(for name: String) -> (folded: [String], exact: [String]) {
        let clean = name.replacingOccurrences(of: "\\s*\\(\\d{4}\\)$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var folded: [String] = []
        var exact: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            let f = NewsMatch.fold(t)
            guard t.count >= 4, !generic.contains(f) else { return }
            if !t.contains(" ") {
                // One word: needs its capital, and five letters.
                if t.count >= 5, t.first?.isUppercase == true || t.first?.isNumber == true { exact.append(t) }
            } else if !folded.contains(f) {
                folded.append(f)
            }
        }
        add(clean)
        for separator in [": ", " - ", " – ", " — "] where clean.contains(separator) {
            let parts = clean.components(separatedBy: separator)
            if let sub = parts.last, sub.count >= 6 { add(sub) }
            // And the series name before it, when it is two words or more:
            // headlines say "LEGO Batman" and "Kingdom Hearts", not the full
            // title. One word ("Control:") would be a common noun.
            if let head = parts.first, head.split(separator: " ").count >= 2 { add(head) }
        }
        return (folded, exact)
    }

    /// The games a story is about, best match first.
    func games(in story: FeedStory) -> [Target] {
        let text = story.title + " | " + story.categories.joined(separator: " | ")
        let folded = NewsMatch.fold(text)
        return targets.filter { t in
            t.patterns.contains { NewsMatch.contains(folded, term: $0) }
                || t.caseSensitive.contains { Self.containsExact(text, word: $0) }
        }
    }

    private static func containsExact(_ text: String, word: String) -> Bool {
        var start = text.startIndex
        while let r = text.range(of: word, range: start..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
            start = text.index(after: r.lowerBound)
        }
        return false
    }
}

/// The All view's layout: every story, newest first, in varied shapes.
///
/// Tim, 09-17: *"I really don't want it to be just a list of titles and tiny
/// image previews."* And on the same day, the reason All exists at all: *"I'd
/// be worried without it that maybe stories people might be interested in
/// would get filtered out and go unseen."* So nothing is dropped here — the
/// only thing this decides is what size each story is drawn at.
enum NewsRiver {
    enum Block: Identifiable, Hashable {
        case day(String)
        case big(FeedStory)
        case pair(FeedStory, FeedStory)
        case row(FeedStory)
        /// A site posting several in a row, folded: "IGN posted 6 more".
        case burst(feedID: UUID, stories: [FeedStory])
        case caughtUp

        var id: String {
            switch self {
            case .day(let label): "day|\(label)"
            case .big(let s): "big|\(s.id)"
            case .pair(let a, let b): "pair|\(a.id)|\(b.id)"
            case .row(let s): "row|\(s.id)"
            case .burst(_, let stories): "burst|\(stories.first?.id ?? "")"
            case .caughtUp: "caughtUp"
            }
        }
    }

    /// Stories a site may post in a row before the rest are folded.
    static let burstKeep = 2
    /// How close together "in a row" means.
    static let burstWindow: TimeInterval = 90 * 60

    static func blocks(_ stories: [FeedStory], lastVisit: Date?, expanded: Set<String> = [],
                       now: Date = .now, calendar: Calendar = .current) -> [Block] {
        let sorted = stories.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        var out: [Block] = []
        var currentDay: Date?
        var placedCaughtUp = false
        var shownSinceBig = 0
        var pendingImage: FeedStory?
        // Per feed: when its last story was, how many in this chain are shown,
        // and where its burst block sits.
        var chains: [UUID: (last: Date, shown: Int, burstIndex: Int?)] = [:]

        func flushPending() {
            if let p = pendingImage { out.append(.row(p)); pendingImage = nil }
        }

        for story in sorted {
            let date = story.published ?? .distantPast
            let day = calendar.startOfDay(for: date)
            if day != currentDay {
                flushPending()
                currentDay = day
                out.append(.day(label(for: day, now: now, calendar: calendar)))
                shownSinceBig = 99 // the first image story of a day leads it
                chains = [:]
            }
            if !placedCaughtUp, let lastVisit, date <= lastVisit, out.contains(where: Self.isStory) {
                flushPending()
                out.append(.caughtUp)
                placedCaughtUp = true
            }

            // Bursts.
            if var chain = chains[story.feedID], chain.last.timeIntervalSince(date) <= burstWindow {
                chain.last = date
                if chain.shown >= burstKeep {
                    if let i = chain.burstIndex, case .burst(let feed, var list) = out[i] {
                        list.append(story)
                        out[i] = .burst(feedID: feed, stories: list)
                    } else {
                        flushPending()
                        out.append(.burst(feedID: story.feedID, stories: [story]))
                        chain.burstIndex = out.count - 1
                    }
                    chains[story.feedID] = chain
                    continue
                }
                chain.shown += 1
                chains[story.feedID] = chain
            } else {
                chains[story.feedID] = (date, 1, nil)
            }

            // Shape.
            if story.imageURL != nil {
                if shownSinceBig >= 6 {
                    flushPending()
                    out.append(.big(story))
                    shownSinceBig = 0
                } else if let p = pendingImage {
                    out.append(.pair(p, story))
                    pendingImage = nil
                    shownSinceBig += 2
                } else {
                    pendingImage = story
                }
            } else {
                flushPending()
                out.append(.row(story))
                shownSinceBig += 1
            }
        }
        flushPending()
        // Expanded bursts become rows where they sat.
        if !expanded.isEmpty {
            out = out.flatMap { block -> [Block] in
                if case .burst(_, let list) = block, expanded.contains(block.id) {
                    return list.map { .row($0) }
                }
                return [block]
            }
        }
        return out
    }

    private static func isStory(_ b: Block) -> Bool {
        switch b {
        case .big, .pair, .row, .burst: true
        default: false
        }
    }

    static func label(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: y) {
            return "Yesterday"
        }
        if day == calendar.startOfDay(for: .distantPast) { return "Undated" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// For You: your games first, then the rest ranked. It reorders; it never
/// hides — everything here is also in All, and the page says so.
enum NewsForYou {
    struct GameGroup: Identifiable, Hashable {
        let gameID: UUID
        let name: String
        let statusRaw: String
        let stories: [FeedStory]
        var id: UUID { gameID }
    }

    struct Page {
        var yourGames: [GameGroup]
        var picked: [FeedStory]
    }

    /// Statuses whose news leads the page.
    static let leadStatuses: Set<String> = ["playing", "paused", "wishlist", "queued", "ongoing"]

    static func page(_ stories: [FeedStory], matcher: GameNewsMatcher, owned: Set<NewsTopic>,
                     groups: [UUID: FeedCatalog.Group], now: Date = .now,
                     window: TimeInterval = 4 * 86_400) -> Page {
        let recent = stories.filter { ($0.published ?? .distantPast) > now.addingTimeInterval(-window) }
        var byGame: [UUID: (target: GameNewsMatcher.Target, stories: [FeedStory])] = [:]
        var used: Set<String> = []
        var anyGame: Set<String> = []
        for story in recent {
            let hits = matcher.games(in: story)
            if !hits.isEmpty { anyGame.insert(story.id) }
            guard let lead = hits.first(where: { leadStatuses.contains($0.statusRaw) }) else { continue }
            byGame[lead.gameID, default: (lead, [])].stories.append(story)
            used.insert(story.id)
        }
        let yourGames = byGame.values.map { entry in
            GameGroup(gameID: entry.target.gameID, name: entry.target.name, statusRaw: entry.target.statusRaw,
                      stories: entry.stories.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) })
        }
        .sorted { ($0.stories.first?.published ?? .distantPast) > ($1.stories.first?.published ?? .distantPast) }

        func score(_ s: FeedStory) -> Double {
            var v = 0.0
            if anyGame.contains(s.id) { v += 3 }
            if owned.contains(where: { $0.matches(s, group: groups[s.feedID]) }) { v += 2 }
            if s.imageURL != nil { v += 1 }
            let hours = now.timeIntervalSince(s.published ?? now) / 3600
            return v - hours / 12
        }
        let picked = recent.filter { !used.contains($0.id) }
            .map { ($0, score($0)) }
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .map(\.0)
        return Page(yourGames: yourGames, picked: Array(picked))
    }
}
