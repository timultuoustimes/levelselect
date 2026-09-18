import Foundation

/// Universal search: one field for games, tracker items, notes, news and
/// releases, then IGDB. Designed on the canvas with Tim, 09-18 — the search
/// tab beside the tab bar rather than a sixth tab, grouped results, IGDB last
/// so a game you don't have is one tap from Add.
///
/// Pure matching here; the tab gathers what to match against.
enum UniversalSearch {
    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case all, games, trackers, journal, news
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .games: "Games"
            case .trackers: "Trackers"
            case .journal: "Journal"
            case .news: "News"
            }
        }
    }

    /// Queries shorter than this match only whole-word starts, so "ha"
    /// finds Hades and Hollow Knight's "Hallownest" but not every "that".
    static let looseAfter = 3

    /// Every word of the query appears in the text: "silk act" finds
    /// "Hollow Knight: Silksong — Act 3". Accents and case aside.
    static func matches(_ text: String, _ query: String) -> Bool {
        let words = terms(query)
        guard !words.isEmpty else { return false }
        let hay = NewsMatch.fold(text)
        return words.allSatisfy { word in
            word.count >= looseAfter ? hay.contains(word) : startsAWord(hay, word)
        }
    }

    static func terms(_ query: String) -> [String] {
        NewsMatch.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func startsAWord(_ hay: String, _ word: String) -> Bool {
        var start = hay.startIndex
        while let r = hay.range(of: word, range: start..<hay.endIndex) {
            if r.lowerBound == hay.startIndex || !hay[hay.index(before: r.lowerBound)].isLetter { return true }
            start = hay.index(after: r.lowerBound)
        }
        return false
    }

    /// Better matches first: the name starts with the query, then a word
    /// starts with it, then it's somewhere inside.
    static func rank(_ text: String, _ query: String) -> Int {
        let hay = NewsMatch.fold(text)
        let q = NewsMatch.fold(query).trimmingCharacters(in: .whitespaces)
        if hay.hasPrefix(q) { return 0 }
        if startsAWord(hay, q) { return 1 }
        return 2
    }

    /// A line of a long note around the first match, so a result shows why
    /// it matched: "…got into the inverted castle. Galamoth next…".
    static func snippet(_ text: String, _ query: String, radius: Int = 48) -> String {
        let flat = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let first = terms(query).first else { return String(flat.prefix(radius * 2)) }
        let folded = NewsMatch.fold(flat)
        guard let r = folded.range(of: first) else { return String(flat.prefix(radius * 2)) }
        let at = folded.distance(from: folded.startIndex, to: r.lowerBound)
        let lower = min(max(0, at - radius), flat.count)
        let upper = min(flat.count, at + first.count + radius)
        let start = flat.index(flat.startIndex, offsetBy: lower)
        let end = flat.index(flat.startIndex, offsetBy: upper)
        return (lower > 0 ? "…" : "") + flat[start..<end].trimmingCharacters(in: .whitespaces)
            + (upper < flat.count ? "…" : "")
    }

    /// Recent searches: newest first, no repeats, eight at most.
    static func remember(_ query: String, in recent: [String]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return recent }
        return Array(([q] + recent.filter { NewsMatch.fold($0) != NewsMatch.fold(q) }).prefix(8))
    }
}
