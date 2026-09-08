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
        case notASheetsLink, exportDisabled, offline, empty
        var errorDescription: String? {
            switch self {
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
    static func exportURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host()?.lowercased(),
              host == "docs.google.com" || host.hasSuffix(".docs.google.com")
        else { return nil }
        let parts = url.pathComponents
        guard let d = parts.firstIndex(of: "d"), parts.count > d + 1 else { return nil }
        let id = parts[d + 1]
        guard !id.isEmpty, id != "e" else { return nil }   // /d/e/ is a published-app URL, not a sheet id
        var gid: String?
        if let fragment = url.fragment, let m = fragment.range(of: "gid=") {
            gid = String(fragment[m.upperBound...]).split(separator: "&").first.map(String.init)
        }
        if gid == nil, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            gid = items.first { $0.name == "gid" }?.value
        }
        var out = "https://docs.google.com/spreadsheets/d/\(id)/export?format=csv"
        if let gid, !gid.isEmpty { out += "&gid=\(gid)" }
        return URL(string: out)
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
            .map { $0.map { $0.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces) } }
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
        let nameKeys = ["name", "item", "trinket", "title", "collectible", "charm", "boss", "objective", "thing"]
        let headerIdx = rows.firstIndex { row in
            row.contains { c in nameKeys.contains(where: { c.lowercased().contains($0) }) && !prose(c) }
        } ?? rows.firstIndex { row in row.filter { !$0.isEmpty }.count >= 2 && !prose(cell(row, 0)) }
        guard let headerIdx else { return "" }
        let header = rows[headerIdx]
        var end = header.count
        for i in header.indices where header[i].isEmpty { end = i; break }
        guard end >= 1, !cell(header, 0).isEmpty else { return "" }

        func line(_ row: [String]) -> String {
            "| " + (0..<end).map { cell(row, $0) }.joined(separator: " | ") + " |"
        }
        var out = [line(header), "|" + String(repeating: " --- |", count: end)]
        var i = headerIdx + 1
        while i < rows.count {
            let row = rows[i]
            if blank(row) {
                // Look past the gap: more of the list, or something else?
                let next = rows[(i + 1)...].first { !blank($0) }
                guard let next, !cell(next, 0).isEmpty, !prose(cell(next, 0)) else { break }
                i += 1
                continue
            }
            if (0..<end).contains(where: { !cell(row, $0).isEmpty }) { out.append(line(row)) }
            i += 1
        }
        return out.count > 2 ? out.joined(separator: "\n") : ""
    }

    /// The whole road: link → export → CSV → table text ready to parse.
    static func table(from link: String) async throws -> String {
        guard let export = exportURL(from: link) else { throw Failure.notASheetsLink }
        let csv = try await fetchCSV(export)
        let table = markdownTable(fromCSV: csv)
        guard !table.isEmpty else { throw Failure.empty }
        return table
    }
}
