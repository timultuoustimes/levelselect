import Foundation

/// "Paste a Google Sheets link" — the half of "import my community sheet"
/// that was never in dispute.
///
/// The general importer was declined on 2026-08-19 and the decline's stated
/// reasons were shown wrong on 08-20 (a public sheet needs an API key, not
/// OAuth; the CSV route is an undocumented adapter an owner can switch off).
/// What survived was the reason that was never about auth: every community
/// sheet is a snowflake, so a *general* importer is a permanent per-sheet
/// mapping burden. This is the tier below that. A link becomes its CSV
/// export, the CSV becomes the markdown table `TrackerListParser` already
/// reads, and the person reviews the result exactly as they would a pasted
/// list. No key, no account, no model, and an honest sentence when an owner
/// has disabled export.
enum SheetsLinkImport {

    enum Failure: LocalizedError {
        case notASheetsLink, exportDisabled, offline, empty, notAList
        var errorDescription: String? {
            switch self {
            case .notAList:       "This tab doesn't look like a list — it may be a planner or a calculator. Pick another tab."
            case .notASheetsLink: "That isn't a Google Sheets link."
            case .exportDisabled: "This sheet's owner has turned off downloading, so it can't be read from here. Ask them for a copy, or paste the rows."
            case .offline:        "Couldn't reach Google Sheets."
            case .empty:          "That sheet is empty, or the tab has no rows."
            }
        }
    }

    /// `https://docs.google.com/spreadsheets/d/<id>/edit#gid=<tab>` and its
    /// variants → the CSV export of that tab. The `gid` names a tab; without
    /// one the first tab is what comes back, which is what a person means.
    static func exportURL(from raw: String, gid override: String? = nil) -> URL? {
        guard let id = sheetID(from: raw) else { return nil }
        let gid = override ?? tabID(from: raw)
        var out = "https://docs.google.com/spreadsheets/d/\(id)/export?format=csv"
        if let gid, !gid.isEmpty { out += "&gid=\(gid)" }
        return URL(string: out)
    }

    static func sheetID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host()?.lowercased(),
              host == "docs.google.com" || host.hasSuffix(".docs.google.com")
        else { return nil }
        let parts = url.pathComponents
        guard let d = parts.firstIndex(of: "d"), parts.count > d + 1 else { return nil }
        let id = parts[d + 1]
        guard !id.isEmpty, id != "e" else { return nil }   // /d/e/ is a published-app URL, not a sheet id
        return id
    }

    /// The tab a link names, if it names one.
    static func tabID(from raw: String) -> String? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if let fragment = url.fragment, let m = fragment.range(of: "gid=") {
            return String(fragment[m.upperBound...]).split(separator: "&").first.map(String.init)
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "gid" }?.value
    }

    // MARK: Tabs

    struct Tab: Identifiable, Hashable, Sendable {
        let name: String
        let gid: String
        var id: String { gid }
    }

    /// Every tab in the sheet, read off its public page — the export only
    /// ever answers for one, and a link with no `gid` gets the first, which on
    /// a team-builder sheet is the one tab that isn't a list. Undocumented, so
    /// an empty answer just means "offer the first tab", never an error.
    static func tabs(for link: String) async -> [Tab] {
        guard let id = sheetID(from: link),
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/htmlview") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return [] }
        return tabs(inPage: html)
    }

    static func tabs(inPage html: String) -> [Tab] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\{name:\s*"((?:[^"\\]|\\.)*)",[^{}]*?gid:\s*"(\d+)""#) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let n = Range(m.range(at: 1), in: html), let g = Range(m.range(at: 2), in: html) else { return nil }
            let gid = String(html[g])
            guard seen.insert(gid).inserted else { return nil }
            let raw = String(html[n])
            // The page escapes names as JS strings.
            let name = (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8),
                                                          options: .fragmentsAllowed)) as? String ?? raw
            return Tab(name: name, gid: gid)
        }
    }

    /// Whether a string is worth trying as a link at all.
    static func looksLikeLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.contains("\n") && t.lowercased().hasPrefix("http") && t.contains("docs.google.com")
    }

    /// The tab's rows, as CSV text. Google answers a disabled export with an
    /// HTML sign-in page and a 200, not an error — so the body is checked,
    /// not the status.
    static func fetchCSV(_ export: URL) async throws -> String {
        var request = URLRequest(url: export)
        request.timeoutInterval = 30
        request.setValue("text/csv,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.offline }
        let http = response as? HTTPURLResponse
        let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.exportDisabled }
        let head = text.prefix(200).lowercased()
        if type.contains("text/html") || head.contains("<html") || head.contains("<!doctype")
            || (http?.statusCode ?? 200) >= 400 {
            throw Failure.exportDisabled
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        return text
    }

    /// CSV → the markdown table the list parser already understands.
    ///
    /// Header aliasing, location guessing and category splitting all live in
    /// `TrackerListParser`; this only changes the punctuation. Pipes inside a
    /// cell would split a column, so they become slashes.
    static func markdownTable(fromCSV csv: String) -> String {
        let rows = CSVImport.parseCSV(csv)
            .map { $0.map { cell -> String in
                let c = clean(cell.replacingOccurrences(of: "|", with: "/"))
                return isFormula(c) ? "" : c
            } }
        // Three shapes, tried from the most particular: the same header over
        // block after block (Final Fantasy VII), a grid of checkboxes beside
        // names (Hollow Knight, The Witcher 3), then one table.
        if let blocks = repeatedHeaderTable(rows) { return blocks }
        if let grid = checkboxGrid(rows) { return grid }
        return singleTable(rows)
    }

    static func isBool(_ s: String) -> Bool {
        let u = s.uppercased()
        return u == "TRUE" || u == "FALSE"
    }

    /// A banner cell repeats its words across a merged row ("PROLOGUE &
    /// WHITE ORCHARD      PROLOGUE & WHITE ORCHARD …"): once is enough.
    static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("   ") else { return t }
        let parts = t.components(separatedBy: "   ")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let first = parts.first, parts.allSatisfy({ $0 == first }) { return first }
        return t
    }

    /// A sheet's own arithmetic — "QUEST COMPLETION = 0%" — is not content.
    static func isFormula(_ s: String) -> Bool {
        s.range(of: #"=\s*-?\d+(\.\d+)?\s*%"#, options: .regularExpression) != nil
    }

    /// A title from a cell: its first line, when the rest is a paragraph
    /// ("NORTHERN REALMS\nAbility: Draw a card…").
    static func titleText(_ s: String) -> String? {
        let first = s.split(separator: "\n", omittingEmptySubsequences: true).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty, first.count <= 40, first.split(separator: " ").count <= 6,
              !isFormula(first), first.filter(\.isLetter).count >= 3,
              // "2x Wolfsbane" is an ingredient, not a heading.
              first.range(of: #"^\d+\s*[x×]\s"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return first
    }

    /// Words that head a column rather than name a list.
    static func isGenericHeader(_ s: String) -> Bool {
        let w = TrackerListParser.words(s)
        return !w.isEmpty && w.allSatisfy { ["name", "names", "title", "item", "items", "location", "locations",
                                              "done", "card", "cards", "player", "quest", "quests"].contains($0) }
    }

    private static func isProse(_ s: String) -> Bool {
        s.count > 60 || s.split(separator: " ").count > 9 || s.contains("\n")
    }

    private static func mdCell(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
    }

    // MARK: Repeated header blocks

    /// **The same header, block after block**, each under a title row:
    /// `1 · 1ST REACTOR`, then `Category | Found | Name | Description`, then
    /// its items. Read as one table with the title as each row's Location, so
    /// a Category column can make the lists and the areas become places.
    static func repeatedHeaderTable(_ rows: [[String]]) -> String? {
        func key(_ row: [String]) -> String? {
            let filled = row.filter { !$0.isEmpty }
            guard filled.count >= 2, !filled.contains(where: isProse),
                  row.contains(where: { TrackerListParser.isNameHeader($0) }) else { return nil }
            return row.map { $0.lowercased() }.joined(separator: "\u{1F}")
        }
        var counts: [String: Int] = [:]
        for row in rows { if let k = key(row) { counts[k, default: 0] += 1 } }
        guard let (headerKey, count) = counts.max(by: { $0.value < $1.value }), count >= 3 else { return nil }
        let headerIdxs = rows.indices.filter { key(rows[$0]) == headerKey }
        let header = rows[headerIdxs[0]]
        guard let start = header.firstIndex(where: { !$0.isEmpty }),
              let last = header.lastIndex(where: { !$0.isEmpty }) else { return nil }
        // Boxes under unnamed header cells beside several list names are a
        // checkbox grid, not blocks (The Witcher 3 repeats "MAIN QUESTS ·
        // SIDE QUESTS" per region).
        let firstEnd = headerIdxs.count > 1 ? headerIdxs[1] : rows.count
        let block = rows[(headerIdxs[0] + 1)..<firstEnd]
        if header.filter(TrackerListParser.isNameHeader).count >= 2,
           block.contains(where: { row in row.enumerated().contains { c, v in
               isBool(v) && (!header.indices.contains(c) || header[c].isEmpty) } }) {
            return nil
        }
        // A box column just past the header's last title is its Done column.
        var headerCells = header
        var spanEnd = last
        for c in (last + 1)...(last + 2) {
            let below = block.map { $0.indices.contains(c) ? $0[c] : "" }.filter { !$0.isEmpty }
            if below.count >= 2, below.allSatisfy(isBool) {
                while headerCells.count <= c { headerCells.append("") }
                headerCells[c] = "Done"
                spanEnd = c
                break
            }
        }
        let span = start...spanEnd
        let hasLocation = headerCells.contains { h in
            TrackerListParser.words(h).contains { ["location", "area", "region", "where"].contains($0) }
        }
        var out = ["| " + span.map { mdCell(headerCells[$0]) }.joined(separator: " | ")
                   + (hasLocation ? "" : " | Location") + " |",
                   "|" + String(repeating: " --- |", count: span.count + (hasLocation ? 0 : 1))]
        for (n, h) in headerIdxs.enumerated() {
            // The title: the nearest filled row above, its words without the
            // block number.
            var title = ""
            var j = h - 1
            while j >= 0, h - j <= 3 {
                let words = rows[j].filter { !$0.isEmpty && Double($0) == nil && !isProse($0) && !isBool($0) }
                if !words.isEmpty { title = TrackerListParser.titled(words.joined(separator: " ")); break }
                j -= 1
            }
            let end = n + 1 < headerIdxs.count ? headerIdxs[n + 1] : rows.count
            for r in (h + 1)..<end {
                let row = rows[r]
                let cells = span.map { row.indices.contains($0) ? row[$0] : "" }
                // A row is an item when its name cell is filled; titles and
                // blanks between blocks aren't.
                guard cells.filter({ !$0.isEmpty }).count >= 2 else { continue }
                out.append("| " + cells.map(mdCell).joined(separator: " | ")
                           + (hasLocation ? "" : " | " + mdCell(title)) + " |")
            }
        }
        return out.count > 2 ? out.joined(separator: "\n") : nil
    }

    // MARK: Checkbox grid

    /// **Checkboxes beside names, in columns**, lists stacked under title
    /// rows — the shape most community checklists take. Google exports a
    /// checkbox as TRUE/FALSE, so the ticks come with it.
    ///
    /// Either side: Hollow Knight puts the box before the name, The Witcher 3
    /// after. A run of boxes on one item is a counter (four mask shards). A
    /// title alone on its row, over another title row, is a region — "PROLOGUE
    /// & WHITE ORCHARD" over "MAIN QUESTS · SIDE QUESTS" — and becomes the
    /// location of what follows.
    static func checkboxGrid(_ rows: [[String]]) -> String? {
        let width = rows.map(\.count).max() ?? 0
        func cell(_ r: Int, _ c: Int) -> String {
            guard c >= 0, rows[r].indices.contains(c) else { return "" }
            return rows[r][c]
        }
        func text(_ r: Int, _ c: Int) -> String? {
            let v = cell(r, c)
            return v.isEmpty || isBool(v) ? nil : v
        }
        struct Run { let start: Int; let end: Int; let checked: Int }
        var runsByRow: [[Run]] = []
        var nameAfter = 0, nameBefore = 0, boxes = 0
        for r in rows.indices {
            var runs: [Run] = []
            var c = 0
            while c < width {
                guard isBool(cell(r, c)) else { c += 1; continue }
                let s = c
                var checked = 0
                while c < width, isBool(cell(r, c)) {
                    if cell(r, c).uppercased() == "TRUE" { checked += 1 }
                    c += 1
                }
                runs.append(Run(start: s, end: c, checked: checked))
                boxes += c - s
                if text(r, c) != nil { nameAfter += 1 }
                if text(r, s - 1) != nil { nameBefore += 1 }
            }
            runsByRow.append(runs)
        }
        guard boxes >= 8, nameAfter + nameBefore >= 6 else { return nil }
        // One header naming one list, over a table whose boxes sit in an
        // unnamed column beside it, is a table with a Done column (The
        // Witcher 3's trophies). Several list names across the header row are
        // a grid (MAIN QUESTS · SIDE QUESTS).
        if let h = rows.indices.first(where: { r in
            let row = rows[r]
            return row.filter { !$0.isEmpty }.count >= 2 && runsByRow[r].isEmpty
                && !row.contains(where: isProse) && row.contains(where: TrackerListParser.isNameHeader)
        }), rows[h].filter({ TrackerListParser.isNameHeader($0) }).count == 1,
           let span = rows[h].firstIndex(where: { !$0.isEmpty }).flatMap({ first in
               rows[h].lastIndex(where: { !$0.isEmpty }).map { first...($0 + 2) } }),
           let nameCol = rows[h].firstIndex(where: TrackerListParser.isNameHeader),
           let next = rows.indices.first(where: { $0 > h && !runsByRow[$0].isEmpty }),
           text(next, nameCol) != nil,
           runsByRow[next].allSatisfy({ span.contains($0.start) && abs($0.start - nameCol) <= 4 }) {
            return nil
        }
        let boxFirst = nameAfter > nameBefore

        struct Entry { var name: String; var col: Int; var detail: String?; var checked: Int; var total: Int; var row: Int }
        var entries: [Entry] = []
        var entryCols = Set<Int>()
        // Rows carrying boxes but no name continue the item above them in
        // that column — another copy of a Gwent card.
        var lastByCol: [Int: Int] = [:]
        for r in rows.indices {
            var rowCols = Set<Int>()
            for run in runsByRow[r] {
                let nameCol = boxFirst ? run.end : run.start - 1
                if let name = text(r, nameCol) {
                    entries.append(Entry(name: name, col: nameCol, detail: nil,
                                         checked: run.checked, total: run.end - run.start, row: r))
                    lastByCol[nameCol] = entries.count - 1
                    rowCols.insert(nameCol)
                    entryCols.insert(nameCol)
                } else if boxFirst, let i = entries.indices.last, entries[i].row == r,
                          entries[i].col == run.start - 1 {
                    // More boxes straight after a box-first name: its parts.
                    entries[i].checked += run.checked
                    entries[i].total += run.end - run.start
                } else if let i = lastByCol[nameCol], cell(r, nameCol).isEmpty,
                          rows.indices.contains(r - 1), entries[i].row <= r - 1,
                          (entries[i].row..<r).allSatisfy({ rr in text(rr, nameCol) == nil || rr == entries[i].row }) {
                    entries[i].checked += run.checked
                    entries[i].total += run.end - run.start
                    rowCols.insert(nameCol)
                }
            }
            // A column with nothing in this row ends its continuation.
            for (col, _) in lastByCol where !rowCols.contains(col) && !cell(r, col).isEmpty {
                lastByCol[col] = nil
            }
        }
        guard entries.count >= 3 else { return nil }
        // Details: the first text beside the item that isn't another list.
        for i in entries.indices {
            let r = entries[i].row
            let from = boxFirst ? entries[i].col + 1 : entries[i].col + 1 + 1
            for c in from...(from + 2) where !entryCols.contains(c) {
                if isBool(cell(r, c)) { break }
                if let d = text(r, c), !isProse(d), !isGenericHeader(d) { entries[i].detail = d; break }
            }
        }

        // Titles: text in (or just left of) a list's column that isn't an
        // item there, with that column's items next — past any rows of plain
        // column headers ("NAME · INGREDIENTS").
        let itemRows = Dictionary(grouping: entries.indices, by: { entries[$0].row })
        func itemCols(_ r: Int) -> Set<Int> { Set((itemRows[r] ?? []).map { entries[$0].col }) }
        func headerOnly(_ r: Int) -> Bool {
            guard itemRows[r] == nil, rows[r].contains(where: isGenericHeader) else { return false }
            return rows[r].enumerated().allSatisfy { c, v in
                v.isEmpty || isGenericHeader(v) || !entryCols.contains(c)
            }
        }
        func nextContent(after r: Int) -> Int? {
            rows.indices.first { $0 > r && rows[$0].contains { !$0.isEmpty } && !headerOnly($0) }
        }
        func titles(_ r: Int) -> [Int: String] {
            let taken = itemCols(r)
            var out: [Int: String] = [:]
            for c in entryCols where !taken.contains(c) {
                // The cell itself, or — when that's empty — the one just
                // left of it, if that isn't another list's column.
                let source = cell(r, c).isEmpty && c > 0 && !entryCols.contains(c - 1) ? c - 1 : c
                if let raw = text(r, source), let t = titleText(raw), !isGenericHeader(t) {
                    out[c] = t
                }
            }
            return out
        }
        var listTitle: [Int: String] = [:]
        var place: [Int: String] = [:]
        var region: String?
        var supers: [(col: Int, title: String)] = []
        var order: [String] = []
        var lists: [String: [(Entry, String?)]] = [:]
        var seen: [String: Set<String>] = [:]
        for r in rows.indices {
            if headerOnly(r) { continue }
            let heads = titles(r)
            if itemRows[r] == nil, rows[r].contains(where: { isProse($0) && titleText($0) == nil }) {
                // A paragraph ends whatever was being titled above it.
                supers = []
                continue
            }
            let next = nextContent(after: r)
            let nextHasItems = next.map { itemRows[$0] != nil } ?? false
            if itemRows[r] == nil, !heads.isEmpty || rows[r].contains(where: { !$0.isEmpty }), let next, !nextHasItems {
                let lone = rows[r].filter { !$0.isEmpty && !isBool($0) }
                let followedByItems = nextContent(after: next).map { itemRows[$0] != nil } ?? false
                let nextHeads = titles(next)
                if followedByItems, !nextHeads.isEmpty {
                    if lone.count == 1, let t = titleText(lone[0]), !isGenericHeader(t),
                       let col = rows[r].firstIndex(where: { !$0.isEmpty }), col <= (entryCols.min() ?? 0) {
                        // One title over a row of titles: a region, the place.
                        region = TrackerListParser.titled(t)
                        supers = []
                        continue
                    }
                    if heads.count >= 2 {
                        // Titles over titles: each names the lists under it,
                        // from the column it sits over.
                        supers = heads.sorted { $0.key < $1.key }
                            .map { (col: $0.key, title: TrackerListParser.titled($0.value)) }
                        continue
                    }
                }
            }
            // Titles for columns whose items come next.
            for (c, t) in heads {
                if let nr = rows.indices.first(where: { $0 > r && (itemCols($0).contains(c) || titles($0)[c] != nil) }),
                   itemCols(nr).contains(c),
                   (r + 1..<nr).allSatisfy({ headerOnly($0) || !rows[$0].contains { !$0.isEmpty } }),
                   t.filter(\.isLetter).count >= 3 {
                    listTitle[c] = TrackerListParser.titled(t)
                }
            }
            for i in itemRows[r] ?? [] {
                let e = entries[i]
                if !boxFirst, !entryCols.contains(e.col - 1), let p = text(r, e.col - 1), !isProse(p),
                   !isGenericHeader(p) {
                    place[e.col] = TrackerListParser.titled(p)
                }
                guard e.name.count <= 100 else { continue }
                let sup = supers.last { $0.col <= e.col }?.title
                let list = sup ?? listTitle[e.col] ?? ""
                let location = sup != nil ? listTitle[e.col] : (place[e.col] ?? region)
                let key = "\(e.name)|\(location ?? "")".lowercased()
                guard seen[list, default: []].insert(key).inserted else { continue }
                if lists[list] == nil { order.append(list) }
                lists[list, default: []].append((e, location))
            }
        }
        // The untitled list first, so it reads under the tab's own name.
        order.sort { ($0.isEmpty ? 0 : 1) < ($1.isEmpty ? 0 : 1) }
        var out: [String] = []
        for list in order {
            if !list.isEmpty { out.append("## \(mdCell(list))") }
            out.append("| Name | Location | Details | Done |")
            out.append("| --- | --- | --- | --- |")
            for (e, location) in lists[list] ?? [] {
                let done = e.total > 1 ? "\(e.checked)/\(e.total)" : (e.checked > 0 ? "yes" : "no")
                out.append("| \(mdCell(e.name)) | \(mdCell(location ?? "")) | \(mdCell(e.detail ?? "")) | \(done) |")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    // MARK: One table

    private static func singleTable(_ rows: [[String]]) -> String {
        func blank(_ row: [String]) -> Bool { !row.contains { !$0.isEmpty } }
        func cell(_ row: [String], _ i: Int) -> String { row.indices.contains(i) ? row[i] : "" }
        func words(_ s: String) -> Int { s.split(separator: " ").count }
        /// A sentence in a cell, not a name — the calculator's caption.
        func prose(_ s: String) -> Bool { s.count > 40 || words(s) > 5 }

        // **The list is not always the first thing on the tab.** Tim's Hollow
        // Knight sheet opens with a banner ("Created by…", "MAKE A COPY…"),
        // then a blank row, THEN the charm table — with three calculators
        // beside it and a notes block below. Read top to bottom as one table
        // it became 229 "items" with "Input 1" among the charms.
        //
        // So: the header is the first row that names a thing the parser
        // recognizes ("Charm", "Name", "Boss"…), else the first row with two
        // filled cells. The table is that row's contiguous columns, up to
        // its first empty one — the gap where a neighboring table begins.
        // A blank row inside a list is skipped; a blank row followed by
        // prose, or by a row with nothing in the name column, is the end.
        // Whole words, so a unit whose skill is "Charmer" isn't a header.
        // A header titles at least two columns; one cell alone is a title.
        let headerIdx = rows.firstIndex { row in
            row.filter { !$0.isEmpty }.count >= 2
                && row.contains { c in !prose(c) && TrackerListParser.isNameHeader(c) }
        } ?? rows.firstIndex { row in row.filter { !$0.isEmpty }.count >= 2 && !prose(cell(row, 0)) }
        guard let headerIdx else { return "" }
        var header = rows[headerIdx]
        // A sheet can start with an empty spacer column; the table starts at
        // its first titled one.
        guard let start = header.firstIndex(where: { !$0.isEmpty }) else { return "" }
        // An unnamed column of checkboxes beside the list is its Done column.
        for c in header.indices where header[c].isEmpty && c > start {
            let below = rows[(headerIdx + 1)...].prefix(40).map { $0.indices.contains(c) ? $0[c] : "" }
            let boxes = below.filter(isBool).count
            if boxes >= 3, boxes * 2 >= below.filter({ !$0.isEmpty }).count, !below.filter({ !$0.isEmpty }).isEmpty {
                header[c] = header.contains("Done") ? "Done \(c)" : "Done"
            }
        }
        var end = header.count
        for i in header.indices where i > start && header[i].isEmpty { end = i; break }
        guard end > start else { return "" }

        func line(_ row: [String]) -> String {
            "| " + (start..<end).map { cell(row, $0) }.joined(separator: " | ") + " |"
        }

        // **A header stacked on headers is a planner, not a list.** The
        // Engage team builder titles each slot's three rows "Name", then
        // "Class", then "Emblem Ring" — read as a list it was 44 rows of
        // units, classes and rings interleaved. A list's second row is an
        // item, never another column title.
        if let next = rows[(headerIdx + 1)...].first(where: { !blank($0) }),
           TrackerListParser.isNameHeader(cell(next, start)),
           TrackerListParser.words(cell(next, start)) != TrackerListParser.words(cell(header, start)) {
            return ""
        }
        // **Tables side by side with no gap between** — Persona 5's "Book
        // Title | Have? | Complete? | Game Title | Have? | Complete?". A
        // second name header after other columns starts a second table.
        var cuts = [start]
        if let first = (start..<end).first(where: { TrackerListParser.isNameHeader(header[$0]) }),
           let kind = TrackerListParser.words(header[first]).last {
            var sawOther = false
            for c in (first + 1)..<end {
                if sawOther, TrackerListParser.words(header[c]).last == kind {
                    cuts.append(c)
                    sawOther = false
                } else {
                    sawOther = true
                }
            }
        }
        if cuts.count > 1 {
            let spans = zip(cuts, cuts.dropFirst() + [end]).map { $0..<$1 }
            let tables = spans.map { span -> String in
                var sub = rows
                for r in sub.indices {
                    sub[r] = span.map { sub[r].indices.contains($0) ? sub[r][$0] : "" } + [""]
                }
                sub[headerIdx] = span.map { header[$0] } + [""]
                return singleTable(Array(sub[headerIdx...]))
            }.filter { !$0.isEmpty }
            return tables.joined(separator: "\n\n")
        }

        var out = [line(header), "|" + String(repeating: " --- |", count: end - start)]
        var i = headerIdx + 1
        while i < rows.count {
            let row = rows[i]
            if blank(row) {
                // Look past the gap: more of the list, or something else?
                let next = rows[(i + 1)...].first { !blank($0) }
                guard let next, !cell(next, start).isEmpty, !prose(cell(next, start)) else { break }
                i += 1
                continue
            }
            if (start..<end).contains(where: { !cell(row, $0).isEmpty }) { out.append(line(row)) }
            i += 1
        }
        return out.count > 2 ? out.joined(separator: "\n") : ""
    }

    /// The whole road: link → export → CSV → table text ready to parse.
    /// A tab with rows that holds no list says so, rather than "empty".
    static func table(from link: String, gid: String? = nil) async throws -> String {
        guard let export = exportURL(from: link, gid: gid) else { throw Failure.notASheetsLink }
        let csv = try await fetchCSV(export)
        let table = markdownTable(fromCSV: csv)
        guard !table.isEmpty else { throw Failure.notAList }
        return table
    }

    // MARK: Roster options from the rest of the sheet

    /// For a roster read from one tab, the choices its fields can offer from
    /// the others: a tab of classes gives Class its options, a tab of rings or
    /// emblems gives Emblem its own. Each tab's first column, read the same
    /// way as any list. Keyed by field id.
    static func referenceOptions(link: String, tabs: [Tab], excluding gid: String?) async -> [String: [String]] {
        var out: [String: [String]] = [:]
        for tab in tabs where tab.gid != gid {
            guard let field = referenceField(forTab: tab.name), out[field] == nil,
                  let table = try? await self.table(from: link, gid: tab.gid) else { continue }
            let names = TrackerListParser.parse(table).categories.flatMap(\.items).map(\.name)
            var seen = Set<String>()
            let unique = names.filter { seen.insert($0.lowercased()).inserted }
            if unique.count >= 2 { out[field] = Array(unique.prefix(200)) }
        }
        return out
    }

    /// Which roster field a reference tab feeds, by its name. Skill tabs feed
    /// nothing — "EmblemSkills" is not a list of emblems.
    static func referenceField(forTab name: String) -> String? {
        let words = TrackerListParser.words(name)
        if words.contains(where: { $0.hasPrefix("skill") }) { return nil }
        if words.contains(where: { $0.hasPrefix("class") || $0 == "job" || $0 == "jobs" }) { return "class" }
        if words.contains(where: { $0.hasPrefix("emblem") || $0.hasPrefix("ring") }) { return "emblem" }
        if words.contains(where: { $0.hasPrefix("weapon") }) { return "weapon" }
        return nil
    }
}
