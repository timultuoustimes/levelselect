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
        var platform: String?
        var status: GameStatus?
        var rating: Int?
        var notes: String?
        var hoursPlayed: Double?
        /// Original line number, for error messages that a human can act on.
        var line: Int
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
        "platform": ["platform", "console", "system", "device", "platforms"],
        "status":   ["status", "state", "list", "shelf", "category", "progress"],
        "rating":   ["rating", "score", "stars", "my rating", "user rating"],
        "notes":    ["notes", "note", "review", "comment", "comments", "my review"],
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

        let normalized = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            rows.append(Row(
                name: name,
                platform: value("platform"),
                status: value("status").flatMap(status(from:)),
                rating: value("rating").flatMap(rating(from:)),
                notes: value("notes"),
                hoursPlayed: value("hours").flatMap(hours(from:)),
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
        case "old favorite", "old favourite", "oldfavorite",
             "played to death", "childhood", "retro favorite":  .oldFavorite
        case "abandoned", "dropped", "quit", "unfinished":  .abandoned
        case "wishlist", "wish list", "wanted":             .wishlist
        default:                                            .backlog
        }
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
