import Foundation

/// Option resolution and run analytics, pure over DTOs and plain values so
/// tests need no store. The web app had both (hand-written per game); this is
/// the generic version every run template gets.
enum RunFieldSupport {

    /// The options a field should offer right now.
    ///
    /// Static `options` unless the field names a category. Category-backed
    /// fields narrow twice, each with a full-list fallback — a filter that
    /// empties the picker would be worse than no filter:
    /// 1. `dependsOn`: items whose `location` matches the named field's
    ///    current value (Hades aspects record their weapon there).
    /// 2. `onlyUnlocked`: items with any recorded progress. The web version
    ///    did exactly this for keepsakes — unlocked ones, or all while the
    ///    tracker is fresh.
    static func options(
        for field: RunFieldDTO,
        categories: [TrackerCategoryDTO],
        progressed: Set<String>,
        values: [String: String]
    ) -> [String] {
        guard let catID = field.optionsFrom,
              let category = categories.first(where: { $0.id == catID })
        else { return field.options }

        var items = category.items
        if let parent = field.dependsOn,
           let chosen = values[parent], !chosen.isEmpty {
            let scoped = items.filter { $0.location == chosen }
            if !scoped.isEmpty { items = scoped }
        }
        if field.onlyUnlocked {
            let unlocked = items.filter { progressed.contains($0.id) }
            if !unlocked.isEmpty { items = unlocked }
        }
        return items.map(\.name)
    }

    /// Whether a field can offer a picker at all (and therefore whether its
    /// values are worth aggregating — free text fragments on every typo).
    static func isOptionBacked(_ field: RunFieldDTO) -> Bool {
        !field.isNumeric && (field.optionsFrom != nil || !field.options.isEmpty)
    }

    // MARK: Lists, numbers and times

    /// A multi or list field's entries, in order, repeats kept.
    static func entries(_ raw: String?) -> [String] {
        (raw ?? "").components(separatedBy: RunFieldDTO.multiSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// How item names and run values are compared: case and spacing aside.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The values a field took across runs that count — every finished run,
    /// or only the won ones.
    static func earnedNames(field: String, winsOnly: Bool,
                            runs: [(fields: [String: String], outcome: RunOutcome)]) -> Set<String> {
        var out = Set<String>()
        for run in runs where run.outcome != .inProgress {
            if winsOnly, run.outcome != .success { continue }
            for value in entries(run.fields[field]) { out.insert(key(value)) }
        }
        return out
    }

    /// A number or a time as entered: "12", "1:23", "1:02:03.5". Times are
    /// stored in seconds.
    static func number(from text: String, time: Bool) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        guard time, t.contains(":") else { return Double(t.replacingOccurrences(of: ",", with: "")) }
        var total = 0.0
        for part in t.split(separator: ":", omittingEmptySubsequences: false) {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Values as a form holds them, made ready to store: numbers and times
    /// become plain numbers (times in seconds), and anything that doesn't
    /// read as one is dropped rather than saved as a score of "abc".
    static func normalized(_ values: [String: String], fields: [RunFieldDTO]) -> [String: String] {
        var out = values
        for field in fields where field.isNumeric {
            guard let raw = values[field.id] else { continue }
            out[field.id] = number(from: raw, time: field.kind == "time").map(plain)
        }
        return out.filter { !$0.value.isEmpty }
    }

    /// A stored number or time, as it's typed back in.
    static func editable(_ raw: String?, field: RunFieldDTO) -> String {
        guard let raw, let n = Double(raw) else { return raw ?? "" }
        return field.kind == "time" ? timeText(n) : plain(n)
    }

    /// Seconds as a speedrun reads them: 1:23.45, 1:02:03.
    static func timeText(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let fraction = seconds - Double(whole)
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        var out = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if fraction > 0.004 {
            out += String(format: ".%02d", Int((fraction * 100).rounded()))
        }
        return out
    }

    static func display(_ raw: String, field: RunFieldDTO) -> String {
        guard field.kind == "time", let seconds = Double(raw) else { return raw }
        return timeText(seconds)
    }

    /// The best value a number or time field reached, and whether the latest
    /// run set it.
    struct Best: Equatable {
        var value: Double
        var text: String
        var setByLatest: Bool
    }

    static func best(for field: RunFieldDTO,
                     runs: [(fields: [String: String], outcome: RunOutcome, startedAt: Date)]) -> Best? {
        guard field.isNumeric, let direction = field.best else { return nil }
        let scored = runs
            .filter { $0.outcome != .inProgress }
            .compactMap { run in run.fields[field.id].flatMap(Double.init).map { ($0, run.startedAt) } }
        guard !scored.isEmpty else { return nil }
        let low = direction == "low"
        guard let top = scored.max(by: { low ? $0.0 > $1.0 : $0.0 < $1.0 }) else { return nil }
        let latest = scored.max { $0.1 < $1.1 }
        let text = field.kind == "time" ? timeText(top.0) : Self.plain(top.0)
        return Best(value: top.0, text: text, setByLatest: latest?.0 == top.0 && scored.count > 1)
    }

    static func plain(_ n: Double) -> String {
        n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }

    // MARK: Analytics

    struct ValueStat: Hashable, Identifiable {
        let value: String
        let wins: Int
        let total: Int
        var id: String { value }
        var winRate: Double { total == 0 ? 0 : Double(wins) / Double(total) }
    }

    struct FieldStats: Identifiable {
        let field: RunFieldDTO
        let rows: [ValueStat]
        var id: String { field.id }
    }

    /// Win rate grouped by each option-backed field's value, across finished
    /// runs. `runs` is (fields, won) so callers decide what "won" means and
    /// tests need no model objects. Multi fields count each of their values
    /// once per run — a run with Zeus and Athena is one appearance for each.
    ///
    /// Rows sort by how often the value was used, not by win rate — with
    /// small run counts a 1/1 sorting above an 8/19 would put noise on top.
    /// The raw fraction ships alongside the percentage for the same reason:
    /// "100%" alone and "1/1" say very different things.
    static func stats(
        fields: [RunFieldDTO],
        runs: [(fields: [String: String], won: Bool)]
    ) -> [FieldStats] {
        fields.compactMap { field in
            guard isOptionBacked(field) else { return nil }
            var byValue: [String: (wins: Int, total: Int)] = [:]
            for run in runs {
                guard let raw = run.fields[field.id], !raw.isEmpty else { continue }
                let values = field.kind == "multi" || field.isRunList
                    ? raw.components(separatedBy: RunFieldDTO.multiSeparator)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    : [raw]
                for value in Set(values) {
                    var entry = byValue[value] ?? (0, 0)
                    entry.total += 1
                    if run.won { entry.wins += 1 }
                    byValue[value] = entry
                }
            }
            guard !byValue.isEmpty else { return nil }
            let rows = byValue
                .map { ValueStat(value: $0.key, wins: $0.value.wins, total: $0.value.total) }
                .sorted { ($0.total, $0.value) > ($1.total, $1.value) }
            return FieldStats(field: field, rows: rows)
        }
    }
}
