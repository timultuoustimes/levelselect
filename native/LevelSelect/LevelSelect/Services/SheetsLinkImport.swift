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
            .filter { row in row.contains { !$0.isEmpty } }
        guard let header = rows.first else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func line(_ cells: [String]) -> String {
            let padded = cells + Array(repeating: "", count: max(0, width - cells.count))
            return "| " + padded.joined(separator: " | ") + " |"
        }
        var out = [line(header), "|" + String(repeating: " --- |", count: width)]
        out += rows.dropFirst().map(line)
        return out.joined(separator: "\n")
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
