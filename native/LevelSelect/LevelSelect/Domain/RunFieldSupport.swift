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
        field.optionsFrom != nil || !field.options.isEmpty
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
                let values = field.kind == "multi"
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
