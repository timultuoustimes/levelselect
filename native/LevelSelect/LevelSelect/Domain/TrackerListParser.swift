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
    }

    struct ParsedCategory: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var items: [ParsedItem]
        /// True when the leading `Foo - ` segment was read as a location. The
        /// review UI exposes this so a wrong guess is one tap to correct.
        var leadingSegmentIsLocation: Bool
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

        guard let headerIdx = lines.firstIndex(where: { line in
            guard line.hasPrefix("|") else { return false }
            let i = lines.firstIndex(of: line)!
            let next = lines.indices.contains(i + 1) ? lines[i + 1] : ""
            return next.hasPrefix("|") && next.allSatisfy { "|-: \t".contains($0) }
        }) else { return result }

        let rawHeaders = cells(lines[headerIdx])
        let map = ColumnMap(headers: rawHeaders.map { $0.lowercased() })
        if map.name == nil {
            result.warnings.append("No name column recognized — used the first column.")
        }
        // Quote the header as the user actually wrote it, not lowercased.
        for unknown in map.unrecognised(rawHeaders) {
            result.warnings.append("Column “\(unknown)” wasn't recognized and was ignored.")
        }

        var items: [ParsedItem] = []
        var seen = Set<String>()
        for line in lines[(headerIdx + 2)...] where line.hasPrefix("|") {
            let values = cells(line)
            guard !values.isEmpty else { continue }
            func value(_ index: Int?) -> String? {
                guard let index, values.indices.contains(index) else { return nil }
                let cleaned = stripMarkdown(values[index])
                return cleaned.isEmpty ? nil : cleaned
            }
            let name = value(map.name ?? 0) ?? ""
            guard !name.isEmpty else { continue }

            items.append(ParsedItem(
                id: uniqueID(from: name, seen: &seen),
                name: name,
                location: value(map.location),
                detail: value(map.detail),
                source: value(map.source)))
        }

        guard !items.isEmpty else { return result }
        result.categories = [ParsedCategory(id: slug(defaultCategoryName),
                                            name: defaultCategoryName,
                                            items: items,
                                            leadingSegmentIsLocation: false)]
        return result
    }

    /// Header aliasing rather than a fixed schema — same approach as the CSV
    /// importer, because no two community checklists agree on column names.
    private struct ColumnMap {
        var name: Int?
        var location: Int?
        var detail: Int?
        var source: Int?

        static let nameKeys = ["name", "item", "trinket", "title", "collectible",
                               "charm", "boss", "objective", "thing"]
        static let locationKeys = ["location", "area", "region", "where", "zone", "map"]
        static let detailKeys = ["effect", "description", "desc", "details", "what"]
        static let sourceKeys = ["notes", "note", "how", "source", "obtain",
                                 "acquisition", "hint"]

        init(headers: [String]) {
            for (i, h) in headers.enumerated() {
                let key = h.trimmingCharacters(in: .whitespaces)
                if name == nil, Self.nameKeys.contains(where: key.contains) { name = i; continue }
                if location == nil, Self.locationKeys.contains(where: key.contains) { location = i; continue }
                if detail == nil, Self.detailKeys.contains(where: key.contains) { detail = i; continue }
                if source == nil, Self.sourceKeys.contains(where: key.contains) { source = i; continue }
            }
        }

        func unrecognised(_ headers: [String]) -> [String] {
            let claimed = Set([name, location, detail, source].compactMap { $0 })
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
                "type": "collectibles",
                "items": category.items.map { item -> [String: Any] in
                    var out: [String: Any] = ["id": item.id, "name": item.name]
                    if let location = item.location { out["location"] = location }
                    if let detail = item.detail { out["description"] = detail }
                    if let source = item.source { out["source"] = source }
                    return out
                },
            ]
            if locked { dict["locked"] = true }
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
