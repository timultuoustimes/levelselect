import Foundation

/// Turns a pasted list — a markdown table, or headed sections of numbered
/// lines — into tracker categories and items, with no model involved.
///
/// Structured input should never round-trip through a generator. A community
/// checklist is already named, located and sorted; handing it to an AI can only
/// add error, cost and a two-minute wait. This parses it directly: instant,
/// free, offline, and incapable of inventing an item that doesn't exist.
///
/// Two real shapes drove the design, both from Tim's vault:
///
/// **Markdown table** (Mina the Hollower) — `| # | Trinket | Effect | Location
/// | Notes |`. Unambiguous once the header is aliased.
///
/// **Sectioned list** (Under the Island) — `Heart Coins (44 Required):` followed
/// by `1. Koala Village - Nia's Bedroom`. Section headers and item boundaries
/// are unambiguous; the split between *name* and *location* genuinely isn't,
/// so the parser guesses and the caller can flip it per category.
enum TrackerListParser {

    // MARK: Result types

    struct ParsedItem: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var location: String?
        var detail: String?
        var source: String?
        /// The original line this came from. Kept so re-interpreting a
        /// category is derived from the source rather than unpicked from
        /// already-split fields — which can't round-trip losslessly.
        var raw: String = ""
        /// Already ticked in the source — a sheet's own checkbox.
        var done = false
        /// A counter: the source's boxes for one item (four mask shards).
        var count: Int? = nil
        var countTarget: Int? = nil
        var missable = false
        /// Season, weather, biome — what a life sim filters by.
        var tags: [String] = []
    }

    struct ParsedCategory: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var items: [ParsedItem]
        /// True when the leading `Foo - ` segment was read as a location. The
        /// review UI exposes this so a wrong guess is one tap to correct.
        var leadingSegmentIsLocation: Bool
        /// "roster" when the table's name column says the rows are characters
        /// ("Unit", "Character"); nil for an ordinary list.
        var kind: String? = nil
        /// What a roster's items record — set by the import screen, which
        /// can fill choices from the sheet's other tabs.
        var fields: [TrackerFieldDTO] = []
    }

    enum Format: String, Sendable {
        case markdownTable
        case sectionedList
        case plainList
        case empty
    }

    struct Result: Sendable {
        var categories: [ParsedCategory] = []
        var format: Format = .empty
        /// Non-fatal notes — lines skipped, columns not recognized. Reported
        /// rather than swallowed, same as the CSV importer.
        var warnings: [String] = []

        var itemCount: Int { categories.reduce(0) { $0 + $1.items.count } }
        var isEmpty: Bool { itemCount == 0 }
    }

    // MARK: Entry point

    static func parse(_ text: String, defaultCategoryName: String = "Imported") -> Result {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { !$0.isEmpty }) else { return Result() }

        if looksLikeMarkdownTable(lines) {
            return parseTable(lines, defaultCategoryName: defaultCategoryName)
        }
        return parseSectioned(lines, defaultCategoryName: defaultCategoryName)
    }

    // MARK: Markdown table

    private static func looksLikeMarkdownTable(_ lines: [String]) -> Bool {
        // A header row followed by a |---|---| separator. Requiring the
        // separator avoids treating prose containing a stray pipe as a table.
        for (i, line) in lines.enumerated() where line.hasPrefix("|") {
            let next = lines.indices.contains(i + 1) ? lines[i + 1] : ""
            if next.hasPrefix("|"), next.contains("-"),
               next.allSatisfy({ "|-: \t".contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func parseTable(_ lines: [String], defaultCategoryName: String) -> Result {
        var result = Result(format: .markdownTable)

        guard let headerIdx = lines.indices.first(where: { i in
            lines[i].hasPrefix("|") && isSeparator(lines.indices.contains(i + 1) ? lines[i + 1] : "")
        }) else { return result }

        let rawHeaders = cells(lines[headerIdx])
        let map = ColumnMap(headers: rawHeaders)
        if map.name == nil {
            result.warnings.append("No name column recognized — used the first column.")
        }
        // Quote the header as the user actually wrote it, not lowercased.
        for unknown in map.unrecognized(rawHeaders) {
            result.warnings.append("Column “\(unknown)” wasn't recognized and was ignored.")
        }

        // **One paste can carry several tables**, each under a `## Heading`
        // — which is what a spreadsheet tab with a block per section becomes
        // (`SheetsLinkImport`). Each table reads with ITS OWN header and lands
        // in its own category; a heading in force names it. Without headings
        // this is exactly the single-table read it always was.
        var categories: [ParsedCategory] = []
        var seen = Set<String>()
        var seenCategoryIDs = Set<String>()
        // "Charm" over a column of charms is the category's name, and so is a
        // heading written above the table — unless the caller already chose
        // one ("Trinkets"), which is not the generic "Imported" and wins for
        // the first table. Headings between later tables always count.
        let callerNamed = !["imported", "sheet", ""].contains(defaultCategoryName.lowercased())
        var heading: String? = callerNamed ? nil
            : lines[..<headerIdx].last { $0.hasPrefix("#") && !$0.hasPrefix("###") }
                .map { String($0.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
        var columns = map
        var headers = rawHeaders
        var tableName: String? = callerNamed ? nil : ColumnMap.tableName(from: rawHeaders, nameColumn: map.name)
        var rows: [[String]] = []

        /// Rows become items, and the items land in categories: the table's
        /// own name, or — when it has a Category column — one per value, in
        /// the order they first appear (Final Fantasy VII's Treasure, Steals,
        /// Enemy Skills), with the heading in force as each item's location.
        func close() {
            defer { rows = [] }
            guard !rows.isEmpty else { return }
            let group = columns.location == nil ? groupColumn(rows, columns: columns, headers: headers) : nil
            var order: [String] = []
            var buckets: [String: [ParsedItem]] = [:]
            let base = heading ?? tableName ?? defaultCategoryName
            // When nearly every row carries a tick, a row without one is a
            // note or a contents line, not an item.
            func tick(_ values: [String]) -> Bool {
                guard let d = columns.done, values.indices.contains(d) else { return false }
                return isTickValue(values[d])
            }
            let named = rows.filter { row in
                let n = columns.name ?? 0
                return row.indices.contains(n) && !row[n].isEmpty
            }
            let needsTick = columns.done != nil && named.filter(tick).count * 5 >= named.count * 4
            for values in rows {
                if needsTick, !tick(values) { continue }
                func value(_ index: Int?) -> String? {
                    guard let index, values.indices.contains(index) else { return nil }
                    let cleaned = stripMarkdown(values[index])
                    return cleaned.isEmpty ? nil : cleaned
                }
                var name = value(columns.name ?? 0) ?? ""
                guard !name.isEmpty else { continue }
                var missable = false
                if let range = name.range(of: #"\s*\bMISSABLE\b\s*"#, options: .regularExpression) {
                    missable = true
                    name.removeSubrange(range)
                    name = name.trimmingCharacters(in: .whitespaces)
                }
                let progress = value(columns.done).map(Self.progress(from:))
                var item = ParsedItem(
                    id: uniqueID(from: name, seen: &seen),
                    name: name,
                    location: value(columns.location) ?? value(group)
                        ?? (columns.category != nil ? heading : nil),
                    detail: value(columns.detail),
                    source: value(columns.source))
                item.missable = missable
                item.tags = columns.tags.flatMap { Self.tags(from: value($0)) }
                item.done = progress?.done ?? false
                item.count = progress?.count
                item.countTarget = progress?.target
                let bucket = value(columns.category).map(Self.titled) ?? base
                if buckets[bucket] == nil { order.append(bucket) }
                buckets[bucket, default: []].append(item)
            }
            for name in order {
                let id = uniqueID(from: name, seen: &seenCategoryIDs)
                if let existing = categories.firstIndex(where: { $0.name == name }) {
                    categories[existing].items += buckets[name] ?? []
                    continue
                }
                categories.append(ParsedCategory(id: id, name: name, items: buckets[name] ?? [],
                                                 leadingSegmentIsLocation: false,
                                                 kind: columns.roster ? TrackerSchemaJSON.rosterKind : nil))
            }
        }

        var i = headerIdx + 2
        while i < lines.count {
            let line = lines[i]
            defer { i += 1 }
            if line.hasPrefix("#"), !line.hasPrefix("###") {
                // With a Category column the heading is a place, not a list —
                // the rows keep going into the same lists (close() merges by
                // name), each carrying the heading it sat under.
                close()
                let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                heading = name.isEmpty ? nil : name
                continue
            }
            guard line.hasPrefix("|") else { continue }
            if isSeparator(lines.indices.contains(i + 1) ? lines[i + 1] : "") {
                // A new header row: the table before it is complete.
                close()
                headers = cells(line)
                columns = ColumnMap(headers: headers)
                tableName = callerNamed ? nil : ColumnMap.tableName(from: headers, nameColumn: columns.name)
                if columns.category != nil { heading = nil }
                i += 1
                continue
            }
            let values = cells(line)
            guard !values.isEmpty else { continue }
            rows.append(values)
        }
        close()

        guard !categories.isEmpty else { return result }
        result.categories = categories
        return result
    }

    private static func isSeparator(_ line: String) -> Bool {
        line.hasPrefix("|") && line.contains("-") && line.allSatisfy { "|-: \t".contains($0) }
    }

    /// Whether a cell reads as a tick at all — TRUE/FALSE, yes/no, x, ✓, 3/4.
    static func isTickValue(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return ["true", "false", "yes", "no", "x", "✓", "✔", "done", "y", "n", "0", "1"].contains(t)
            || t.range(of: #"^\d+\s*/\s*\d+$"#, options: .regularExpression) != nil
    }

    /// "yes", "TRUE", "x", "✓" → done; "3/4" → a counter three of four in.
    static func progress(from text: String) -> (done: Bool, count: Int?, target: Int?) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let m = t.range(of: #"^(\d+)\s*/\s*(\d+)$"#, options: .regularExpression) {
            let parts = t[m].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if parts.count == 2, parts[1] > 1 {
                return (parts[0] >= parts[1], min(parts[0], parts[1]), parts[1])
            }
        }
        return (["yes", "true", "x", "✓", "✔", "done", "y", "1"].contains(t), nil, nil)
    }

    /// "MAIN QUESTS" → "Main Quests"; anything already mixed-case stays.
    static func titled(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard letters.count > 3, letters == letters.uppercased() else { return text }
        let small: Set<String> = ["of", "the", "and", "a", "in", "on", "to", "for"]
        return text.lowercased().split(separator: " ", omittingEmptySubsequences: false)
            .enumerated()
            .map { i, word in
                // The first LETTER — "(Ursine)" — and "1st", not Foundation's "1St".
                guard !(i > 0 && small.contains(String(word))),
                      let first = word.firstIndex(where: \.isLetter),
                      first == word.startIndex || !word[word.startIndex].isNumber
                else { return String(word) }
                return word[..<first] + word[first].uppercased() + word[word.index(after: first)...]
            }
            .joined(separator: " ")
    }

    /// "Spring, Summer" or "Rain / Snow" as separate tags. "All" and "Any"
    /// are no tag at all: an item for every season shows under every filter.
    static func tags(from cell: String?) -> [String] {
        guard let cell else { return [] }
        let everything: Set<String> = ["all", "any", "all seasons", "any season", "anytime", "any weather", "—", "-", "n/a"]
        var seen = Set<String>()
        return cell.components(separatedBy: CharacterSet(charactersIn: ",/;&\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !everything.contains($0.lowercased()) }
            .map(titled)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// A column that groups the rows: words, not numbers, repeating — Arcana
    /// beside each Persona, Emblem beside each skill. Never the name or a
    /// column already read, and only near the name, so a Gender or Type
    /// column far across a stat sheet doesn't split the list.
    private static func groupColumn(_ rows: [[String]], columns: ColumnMap, headers: [String]) -> Int? {
        let name = columns.name ?? 0
        let claimed = Set([columns.name ?? 0, columns.detail, columns.source, columns.done, columns.category]
            .compactMap { $0 } + columns.tags)
        let n = rows.count
        guard n >= 4 else { return nil }
        for c in 0...min(name + 2, (headers.count - 1)) where !claimed.contains(c) {
            let values = rows.map { $0.indices.contains(c) ? $0[c].trimmingCharacters(in: .whitespaces) : "" }
            let filled = values.filter { !$0.isEmpty }
            guard filled.count >= n * 3 / 4 else { continue }
            let numeric = filled.filter { Double($0) != nil }.count
            guard numeric * 4 <= filled.count else { continue }
            let distinct = Set(filled).count
            if distinct >= 2, distinct <= n / 2, filled.allSatisfy({ $0.count <= 40 }) {
                // Two values on a long list is a flag (Male/Female), not a group.
                if distinct == 2, n > 12 { continue }
                return c
            }
        }
        return nil
    }

    /// Header aliasing rather than a fixed schema — same approach as the CSV
    /// importer, because no two community checklists agree on column names.
    /// A header's words, lowercased: "Emblem Name" → emblem, name;
    /// "EmblemSkills" → emblem, skills. Matching whole words is what stops a
    /// unit whose skill is "Charmer" from reading as a Charm header.
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var previous: Character?
        for ch in text {
            if !(ch.isLetter || ch.isNumber) {
                if !current.isEmpty { out.append(current.lowercased()); current = "" }
            } else {
                if ch.isUppercase, let previous, previous.isLowercase, !current.isEmpty {
                    out.append(current.lowercased()); current = ""
                }
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { out.append(current.lowercased()) }
        return out
    }

    /// Whether a cell reads as the header of a name column.
    static func isNameHeader(_ text: String) -> Bool {
        let w = words(text)
        guard !w.isEmpty, w.count <= 4 else { return false }
        return w.contains { ColumnMap.nameKeys.contains($0) || ColumnMap.entityKeys.contains($0) }
    }

    private struct ColumnMap {
        var name: Int?
        var location: Int?
        var detail: Int?
        var source: Int?
        /// Ticked in the sheet: "Found", "Done", "Have?".
        var done: Int?
        /// What list each row belongs to: "Category".
        var category: Int?
        /// The rows are characters, by the name column's own word.
        var roster = false
        /// Filters: Season, Weather, Tags, Biome.
        var tags: [Int] = []

        /// Words that say "this column is the name" — preferred wherever
        /// they appear.
        static let nameKeys: Set<String> = ["name", "names", "title", "item", "items"]
        /// Words that say what the rows ARE. The first column wearing one is
        /// the name when no column is literally "Name".
        static let entityKeys: Set<String> = ["trinket", "trinkets", "collectible", "collectibles",
                                              "charm", "charms", "boss", "bosses", "objective",
                                              "objectives", "thing", "things", "unit", "units",
                                              "character", "characters", "emblem", "emblems",
                                              "class", "classes", "member", "members", "recruit",
                                              "recruits", "shrine", "shrines", "quest", "quests",
                                              "challenge", "challenges", "achievement", "achievements",
                                              "trophy", "trophies", "card", "cards", "weapon", "weapons",
                                              "recipe", "recipes", "mission", "missions", "request", "requests",
                                              "persona", "personas"]
        static let rosterKeys: Set<String> = ["unit", "units", "character", "characters",
                                              "member", "members", "recruit", "recruits"]
        static let locationKeys: Set<String> = ["location", "locations", "area", "areas", "region",
                                                "where", "zone", "map"]
        static let detailKeys: Set<String> = ["effect", "effects", "description", "desc", "details", "what"]
        static let sourceKeys: Set<String> = ["notes", "note", "how", "source", "obtain", "obtained",
                                              "acquisition", "hint", "hints", "requirement", "requirements",
                                              "unlock"]
        static let doneKeys: Set<String> = ["done", "found", "complete", "completed", "have", "got",
                                            "collected", "owned", "checked", "status", "maxed"]
        static let categoryKeys: Set<String> = ["category", "categories"]
        static let tagKeys: Set<String> = ["season", "seasons", "weather", "tag", "tags", "biome", "biomes"]

        init(headers: [String]) {
            let split = headers.map(TrackerListParser.words)
            func has(_ i: Int, _ keys: Set<String>) -> Bool { split[i].contains(where: keys.contains) }
            name = split.indices.first { has($0, Self.nameKeys) }
                ?? split.indices.first { has($0, Self.entityKeys) }
            if let name {
                // "Unit" over the names, or "Character Name", means a roster.
                roster = has(name, Self.rosterKeys)
            }
            for i in split.indices where i != name {
                if split[i].count <= 2, has(i, Self.tagKeys) { tags.append(i); continue }
                // One-word headers only for these, so "Complete Guide" isn't a tick.
                if done == nil, split[i].count <= 2, has(i, Self.doneKeys) { done = i; continue }
                if category == nil, split[i].count <= 2, has(i, Self.categoryKeys) { category = i; continue }
                if location == nil, has(i, Self.locationKeys) { location = i; continue }
                if detail == nil, has(i, Self.detailKeys) { detail = i; continue }
                if source == nil, has(i, Self.sourceKeys) { source = i; continue }
            }
        }

        /// A header that names the THING — "Charm", "Boss", "Trinket" — is a
        /// category name. "Name" and "Item" are not; they say nothing about
        /// what the rows are.
        static func tableName(from headers: [String], nameColumn: Int?) -> String? {
            guard let nameColumn, headers.indices.contains(nameColumn) else { return nil }
            let word = headers[nameColumn].trimmingCharacters(in: .whitespaces)
            let generic = ["name", "item", "items", "title", "thing", "things", "collectible", "collectibles", "objective",
                           "emblem name", "unit name", "character name", "#"]
            guard !word.isEmpty, !generic.contains(word.lowercased()) else { return nil }
            return word
        }

        func unrecognized(_ headers: [String]) -> [String] {
            let claimed = Set([name, location, detail, source, done, category].compactMap { $0} + tags)
            return headers.enumerated().compactMap { i, h in
                let trimmed = h.trimmingCharacters(in: .whitespaces)
                // A bare "#" index column is expected, not worth warning about.
                if claimed.contains(i) || trimmed.isEmpty || trimmed == "#" { return nil }
                return trimmed
            }
        }
    }

    private static func cells(_ row: String) -> [String] {
        var parts = row.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Sectioned / plain list

    private static func parseSectioned(_ lines: [String], defaultCategoryName: String) -> Result {
        var result = Result(format: .sectionedList)
        // Each raw entry carries the `###` heading in force when it was read,
        // if any — that becomes the item's location.
        var categories: [(name: String, raw: [(body: String, heading: String?)])] = []
        var current: (name: String, raw: [(body: String, heading: String?)])?
        var heading: String?

        for line in lines where !line.isEmpty {
            if let sub = locationHeading(line) {
                heading = sub
                continue
            }
            if let header = sectionHeader(line) {
                if let open = current, !open.raw.isEmpty { categories.append(open) }
                current = (header, [])
                heading = nil
                continue
            }
            guard let body = itemBody(line) else { continue }
            if current == nil { current = (defaultCategoryName, []) }
            current?.raw.append((body, heading))
        }
        if let open = current, !open.raw.isEmpty { categories.append(open) }

        guard !categories.isEmpty else { return result }
        if categories.count == 1 && categories[0].name == defaultCategoryName {
            result.format = .plainList
        }

        var seen = Set<String>()
        result.categories = categories.map { category in
            // An explicit `###` heading beats the guess every time.
            let explicit = category.raw.contains { $0.heading != nil }
            let split = category.raw.map { splitLeading($0.body) }
            // If the leading segment repeats across the section it's a place,
            // not a name — "Koala Village" nine times is a location; "Wallet 1,
            // Wallet 2, Wallet 3" are items. Cheap signal, and right on both of
            // the real lists this was built against.
            let leads = split.compactMap(\.lead)
            let isLocation = !explicit && !leads.isEmpty && Set(leads).count < leads.count

            let items = split.enumerated().map { offset, piece -> ParsedItem in
                let heading = category.raw[offset].heading
                if let heading {
                    return ParsedItem(id: uniqueID(from: piece.whole, seen: &seen),
                                      name: piece.whole, location: heading, raw: piece.whole)
                }
                if let lead = piece.lead, let rest = piece.rest {
                    let name = isLocation ? rest : lead
                    return ParsedItem(id: uniqueID(from: name, seen: &seen),
                                      name: name,
                                      location: isLocation ? lead : nil,
                                      detail: isLocation ? nil : rest,
                                      raw: piece.whole)
                }
                return ParsedItem(id: uniqueID(from: piece.whole, seen: &seen),
                                  name: piece.whole, raw: piece.whole)
            }
            return ParsedCategory(id: slug(category.name), name: category.name,
                                  items: items, leadingSegmentIsLocation: isLocation)
        }
        return result
    }

    /// A markdown sub-heading — `### Koala Village` — used as the *location*
    /// for the items beneath it, rather than as a nested category.
    ///
    /// The schema is two levels deep (category → items) and progress is keyed
    /// per item, so genuine nesting would ripple through the renderer, the
    /// merge engine and the progress maths. Hoisting a repeated location out
    /// of every row into a heading is a *display* problem, and the data
    /// already carries `location` — so `###` fills that field and the renderer
    /// groups by it, which gets the same result with no structural change.
    private static func locationHeading(_ line: String) -> String? {
        guard line.hasPrefix("###") else { return nil }
        let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.count > 80 ? nil : name
    }

    /// `## Heart Coins` or `Heart Coins (44 Required):` → a category.
    /// Deliberately strict on the colon form: the line must end in a colon and
    /// not itself be a list item, so a numbered line containing a colon isn't
    /// mistaken for a header.
    private static func sectionHeader(_ line: String) -> String? {
        if line.hasPrefix("#"), !line.hasPrefix("###") {
            let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return name.isEmpty || name.count > 80 ? nil : name
        }
        guard line.hasSuffix(":"), !line.hasPrefix("-"), !line.hasPrefix("*") else { return nil }
        if line.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil { return nil }
        let name = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
        // Drop a trailing count qualifier — "(44 Required)" is metadata, not
        // part of what the category is called.
        let cleaned = name.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        let final = cleaned.isEmpty ? name : cleaned
        return final.isEmpty || final.count > 80 ? nil : final
    }

    /// Strip list markers. Returns nil for lines that aren't list items —
    /// stray URLs, prose, separators.
    private static func itemBody(_ line: String) -> String? {
        var body = line
        if let match = body.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            body.removeSubrange(match)
        } else if body.hasPrefix("- ") || body.hasPrefix("* ") {
            body.removeFirst(2)
            // Markdown task syntax: "- [ ] Nia's Bedroom".
            if let box = body.range(of: #"^\[[ xX]?\]\s*"#, options: .regularExpression) {
                body.removeSubrange(box)
            }
        } else if body.lowercased().hasPrefix("http") || body.hasPrefix("[") && body.contains("](http") {
            return nil
        }
        body = stripMarkdown(body).trimmingCharacters(in: .whitespaces)
        // A bare separator or a stray fragment isn't an item.
        guard body.count > 1, body.contains(where: \.isLetter) else { return nil }
        return body
    }

    private static func splitLeading(_ body: String) -> (whole: String, lead: String?, rest: String?) {
        // Only " - " with spaces, so hyphenated names ("Hiku-Bird") survive.
        guard let range = body.range(of: " - ") else { return (body, nil, nil) }
        let lead = String(body[body.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !lead.isEmpty, !rest.isEmpty else { return (body, nil, nil) }
        return (body, lead, rest)
    }

    // MARK: Conversion to schema JSON

    /// Turn a parse result into an incoming schema the merge engine can take.
    ///
    /// Imported categories are marked `locked` so a later regeneration can't
    /// quietly replace a checklist the user deliberately pasted in — the same
    /// protection Personal Goals has always had, generalised. That's what makes
    /// importing safe *without* flattening everything into Personal Goals and
    /// losing the section structure.
    static func schemaData(from result: Result, locked: Bool = true) -> Data {
        let categories: [[String: Any]] = result.categories.map { category in
            var dict: [String: Any] = [
                "id": category.id,
                "name": category.name,
                "type": category.kind ?? "collectibles",
                "items": category.items.map { item -> [String: Any] in
                    var out: [String: Any] = ["id": item.id, "name": item.name]
                    if let location = item.location { out["location"] = location }
                    if let detail = item.detail { out["description"] = detail }
                    if let target = item.countTarget, target > 1 { out["countTarget"] = target }
                    if item.missable { out["missable"] = true }
                    if !item.tags.isEmpty { out[TrackerSchemaJSON.filtersKey] = item.tags }
                    if let source = item.source { out["source"] = source }
                    return out
                },
            ]
            if locked { dict["locked"] = true }
            if !category.fields.isEmpty { dict[TrackerSchemaJSON.fieldsKey] = category.fields.map(\.json) }
            return dict
        }
        let root: [String: Any] = ["schemaVersion": 1, "categories": categories]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? TrackerSchemaJSON.emptySchema()
    }

    /// Re-read a category with the opposite interpretation of its leading
    /// segment, for when the heuristic guessed wrong.
    ///
    /// Re-derived from each item's original line rather than by rearranging
    /// the already-split fields: unpicking them can't round-trip, because
    /// "name + detail" and "location + name" don't carry the same information
    /// once they've been separated.
    static func flippingLeadingSegment(_ category: ParsedCategory) -> ParsedCategory {
        var flipped = category
        flipped.leadingSegmentIsLocation.toggle()
        let asLocation = flipped.leadingSegmentIsLocation
        flipped.items = category.items.map { item in
            guard !item.raw.isEmpty else { return item }
            let piece = splitLeading(item.raw)
            guard let lead = piece.lead, let rest = piece.rest else { return item }
            var next = item
            next.name = asLocation ? rest : lead
            next.location = asLocation ? lead : nil
            next.detail = asLocation ? nil : rest
            return next
        }
        return flipped
    }

    // MARK: Shared helpers

    /// `[Lace Glove](https://…)` → `Lace Glove`, plus bold/italic markers.
    static func stripMarkdown(_ text: String) -> String {
        var out = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: "__", with: "")
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func slug(_ text: String) -> String {
        let base = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return base.isEmpty ? "item" : String(base.prefix(60))
    }

    /// Ids must be unique inside a schema — progress is keyed by them, so two
    /// items sharing one would share a checkmark.
    private static func uniqueID(from name: String, seen: inout Set<String>) -> String {
        let base = slug(name)
        var candidate = base
        var n = 2
        while seen.contains(candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        seen.insert(candidate)
        return candidate
    }
}
