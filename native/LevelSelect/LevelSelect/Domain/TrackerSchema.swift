import Foundation

/// Typed view of a tracker schema's JSON (legacy `structuredData` shape,
/// verified against real data). Parsed tolerantly — unknown fields are
/// preserved in the stored JSON and simply not surfaced here.
struct TrackerItemDTO: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let itemDescription: String?
    let location: String?
    let missable: Bool
    let hideUntilDiscovered: Bool
    let maxRank: Int?
    let rankNames: [String]?
    /// Optional schema hint: "pips" | "hearts" | "numbered" | "stepper".
    /// Absent in the built-ins, which infer from the data instead.
    let display: String?
    /// The name this arrived with, kept when the user renames it so the merge
    /// engine can still match it against a future generation.
    var sourceName: String? = nil
    /// The user's own note. Distinct from `itemDescription`, which belongs to
    /// whatever generated or supplied the item and may be replaced freely —
    /// this one is theirs and survives every merge.
    var note: String? = nil
}

struct TrackerCategoryDTO: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let categoryDescription: String?
    let kind: String?          // e.g. "sequence"
    let items: [TrackerItemDTO]
    /// As `TrackerItemDTO.sourceName`.
    var sourceName: String? = nil
}

// MARK: - Run template (roguelikes / Hades)

struct RunFieldDTO: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let kind: String            // "text" | "select"
    let options: [String]
}

struct RunOutcomeDTO: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let result: RunOutcome      // success / failure / neutral
}

struct RunTemplateDTO: Hashable, Sendable {
    let fields: [RunFieldDTO]
    let outcomes: [RunOutcomeDTO]
}

enum TrackerSchemaJSON {
    static let personalGoalsID = "personal-goals"

    /// Parse the run template out of stored schema JSON, if present.
    /// Best-guess win/lose classification for an outcome that only gave us a
    /// label. Roguelike vocabulary varies a lot ("Escaped", "Cleared", "Died",
    /// "Wiped"), so this errs toward `.neutral` rather than guessing wrong —
    /// a mislabeled outcome would quietly skew win rates.
    private static func inferredResult(from label: String) -> RunOutcome {
        let l = label.lowercased()
        let wins = ["win", "won", "victory", "success", "escaped", "escape",
                    "cleared", "clear", "beat", "complete"]
        let losses = ["loss", "lost", "died", "die", "death", "defeat",
                      "failed", "fail", "wiped", "killed"]
        if wins.contains(where: l.contains) { return .success }
        if losses.contains(where: l.contains) { return .failure }
        return .neutral
    }

    static func runTemplate(from data: Data) -> RunTemplateDTO? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["runTemplate"] as? [String: Any] else { return nil }
        let fields: [RunFieldDTO] = ((raw["fields"] as? [[String: Any]]) ?? []).compactMap { f in
            guard let id = f["id"] as? String, let label = f["label"] as? String else { return nil }
            return RunFieldDTO(
                id: id, label: label,
                kind: (f["type"] as? String) ?? "text",
                options: (f["options"] as? [Any])?.compactMap { $0 as? String } ?? []
            )
        }
        // Outcomes arrive in two shapes and both have to work.
        //
        // The AI generator's JSON schema declares `outcomes` as an array of
        // plain STRINGS (`["Won", "Died"]`), while built-in and hand-written
        // schemas use objects (`{id, label, result}`). Accepting only objects
        // meant every AI-generated roguelike tracker silently produced no run
        // template at all — and because `addingDefaultRunTemplate` only
        // checked whether the *key* existed, "Log Runs for This Game" then
        // became a permanent no-op on exactly those games.
        let rawOutcomes = raw["outcomes"] as? [Any] ?? []
        let outcomes: [RunOutcomeDTO] = rawOutcomes.compactMap { entry in
            if let o = entry as? [String: Any] {
                guard let id = o["id"] as? String else { return nil }
                return RunOutcomeDTO(
                    id: id,
                    label: (o["label"] as? String) ?? id.capitalized,
                    result: RunOutcome(rawValue: (o["result"] as? String) ?? "")
                        ?? inferredResult(from: (o["label"] as? String) ?? id)
                )
            }
            if let label = entry as? String, !label.isEmpty {
                return RunOutcomeDTO(
                    id: label.lowercased().replacingOccurrences(of: " ", with: "-"),
                    label: label,
                    result: inferredResult(from: label)
                )
            }
            return nil
        }
        guard !outcomes.isEmpty else { return nil }
        return RunTemplateDTO(fields: fields, outcomes: outcomes)
    }

    /// Parse categories out of stored schema JSON (lenient).
    static func categories(from data: Data) -> [TrackerCategoryDTO] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCats = root["categories"] as? [[String: Any]] else { return [] }
        return rawCats.compactMap { raw in
            guard let id = raw["id"] as? String, let name = raw["name"] as? String else { return nil }
            let rawItems = (raw["items"] as? [[String: Any]]) ?? []
            let items: [TrackerItemDTO] = rawItems.compactMap { item in
                guard let iid = item["id"] as? String, let iname = item["name"] as? String else { return nil }
                return TrackerItemDTO(
                    id: iid,
                    name: iname,
                    itemDescription: item["description"] as? String,
                    location: item["location"] as? String,
                    missable: (item["missable"] as? Bool) ?? false,
                    hideUntilDiscovered: (item["hideUntilDiscovered"] as? Bool) ?? false,
                    maxRank: (item["maxRank"] as? NSNumber)?.intValue,
                    rankNames: (item["rankNames"] as? [Any])?.compactMap { $0 as? String },
                    display: item["display"] as? String,
                    sourceName: item["sourceName"] as? String,
                    note: item["note"] as? String
                )
            }
            return TrackerCategoryDTO(
                id: id,
                name: name,
                categoryDescription: raw["description"] as? String,
                kind: raw["type"] as? String,
                items: items,
                sourceName: raw["sourceName"] as? String
            )
        }
    }

    /// Append a Personal Goals item, preserving all unknown fields in the JSON.
    /// Creates the Personal Goals category if missing. Returns updated data.
    static func addingGoal(named goalName: String, to data: Data) -> Data? {
        addingGoal(named: goalName, id: "goal-\(UUID().uuidString.prefix(8))", to: data)
    }

    /// As above, with the id supplied by the caller.
    ///
    /// Rescuing a completed item that a regenerated tracker dropped needs to
    /// know the goal's id up front, so the progress record can be pointed at
    /// it and the tick survives the move.
    static func addingGoal(named goalName: String, id: String, to data: Data) -> Data? {
        var root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if root["schemaVersion"] == nil { root["schemaVersion"] = 1 }
        var cats = (root["categories"] as? [[String: Any]]) ?? []
        let newItem: [String: Any] = ["id": id, "name": goalName]

        if let idx = cats.firstIndex(where: { ($0["id"] as? String) == personalGoalsID }) {
            var cat = cats[idx]
            var items = (cat["items"] as? [[String: Any]]) ?? []
            items.append(newItem)
            cat["items"] = items
            cats[idx] = cat
        } else {
            cats.append(["id": personalGoalsID, "name": "Personal Goals", "items": [newItem]])
        }
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Minimal empty schema for games that have no tracker yet.
    /// Turn run logging on for a game by injecting a general-purpose run
    /// template into its schema.
    ///
    /// Run logging used to depend entirely on whether the generated or
    /// built-in schema happened to include a `runTemplate` — so Hades had runs
    /// and Dead Cells could never have them, with no say from the player. This
    /// makes it a choice. The template lives inside `jsonData`, so enabling it
    /// is not a SwiftData migration.
    static func addingDefaultRunTemplate(to data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        // Check for a *usable* template, not merely the key's presence. A
        // schema can carry a `runTemplate` that parses to nothing (JSON null,
        // or outcomes in a shape we can't read) — treating that as "already
        // on" made this a silent no-op forever on exactly the games that
        // needed it. A valid custom template (Hades') still short-circuits.
        guard runTemplate(from: data) == nil else { return data }   // already on
        root["runTemplate"] = [
            "fields": [
                ["id": "loadout", "label": "Loadout", "type": "text"],
                ["id": "notes", "label": "Notes", "type": "text"],
            ],
            "outcomes": [
                ["id": "success", "label": "Won"],
                ["id": "failure", "label": "Died"],
                ["id": "neutral", "label": "Abandoned"],
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Turn run logging off. Existing runs are untouched — they stay in the
    /// playthrough and reappear if it's switched back on, so this is never
    /// a destructive action.
    static func removingRunTemplate(from data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        root["runTemplate"] = nil
        return try? JSONSerialization.data(withJSONObject: root)
    }

    static func emptySchema() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": []])) ?? Data()
    }

    /// Rename a category or an item in place.
    ///
    /// Two things are deliberately preserved. The **id never changes**, because
    /// progress is keyed by item id and the merge engine matches on id first —
    /// renaming must not orphan a checkmark or make a regeneration think the
    /// item is new. And the **generator's original name is kept** in
    /// `sourceName` the first time something is renamed, so name-based matching
    /// still works if a later regeneration re-slugs the ids: without it,
    /// renaming "Stages" to "Achievements" would make the next generation
    /// import a second, duplicate category.
    static func renaming(categoryID: String, itemID: String?, to newName: String,
                         in data: Data) -> Data? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let cIdx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }

        var category = cats[cIdx]
        if let itemID {
            var items = (category["items"] as? [[String: Any]]) ?? []
            guard let iIdx = items.firstIndex(where: { ($0["id"] as? String) == itemID })
            else { return nil }
            var item = items[iIdx]
            if item["sourceName"] == nil, let original = item["name"] as? String {
                item["sourceName"] = original
            }
            item["name"] = trimmed
            items[iIdx] = item
            category["items"] = items
        } else {
            if category["sourceName"] == nil, let original = category["name"] as? String {
                category["sourceName"] = original
            }
            category["name"] = trimmed
        }
        cats[cIdx] = category
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Edit an item's user-facing fields. `nil` leaves a field alone; an empty
    /// string clears it.
    ///
    /// `note` is the user's own and is deliberately separate from
    /// `description`, which belongs to whatever generated or supplied the item.
    /// Sharing one field would mean the first regeneration ate everything the
    /// user had written.
    static func editingItem(categoryID: String, itemID: String,
                            name: String? = nil, location: String? = nil,
                            note: String? = nil, in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let cIdx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }
        var category = cats[cIdx]
        var items = (category["items"] as? [[String: Any]]) ?? []
        guard let iIdx = items.firstIndex(where: { ($0["id"] as? String) == itemID })
        else { return nil }
        var item = items[iIdx]

        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed != (item["name"] as? String) {
                if item["sourceName"] == nil, let original = item["name"] as? String {
                    item["sourceName"] = original
                }
                item["name"] = trimmed
            }
        }
        if let location {
            let trimmed = location.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { item.removeValue(forKey: "location") }
            else { item["location"] = trimmed }
        }
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { item.removeValue(forKey: "note") }
            else { item["note"] = trimmed }
        }

        items[iIdx] = item
        category["items"] = items
        cats[cIdx] = category
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Categories the user has locked — imported checklists, hand-curated
    /// content, anything they've said a regeneration may not touch.
    ///
    /// Locking is the general mechanism; Personal Goals is simply the category
    /// that is always locked. It lives in the schema JSON, so none of this is
    /// blocked by frozen Schema V1.
    static func lockedCategoryIDs(in data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = root["categories"] as? [[String: Any]] else { return [] }
        return Set(cats.compactMap { cat in
            (cat["locked"] as? Bool) == true ? cat["id"] as? String : nil
        })
    }

    /// Lock or unlock a category in place.
    static func settingLock(_ locked: Bool, categoryID: String, in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let idx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }
        var cat = cats[idx]
        if locked { cat["locked"] = true } else { cat.removeValue(forKey: "locked") }
        cats[idx] = cat
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Carry the user's own content — Personal Goals, and any locked category —
    /// from an old schema into a newly generated one. Regeneration must never
    /// eat something the user wrote or deliberately imported.
    static func mergingPersonalGoals(from oldData: Data, into newData: Data) -> Data {
        let preserved = preservedCategories(from: oldData)
        guard !preserved.isEmpty,
              var new = (try? JSONSerialization.jsonObject(with: newData)) as? [String: Any]
        else { return mergingGoalsOnly(from: oldData, into: newData) }

        var newCats = (new["categories"] as? [[String: Any]]) ?? []
        // A preserved category REPLACES an incoming one that collides on id,
        // rather than being skipped.
        //
        // The old `where !existing.contains(id)` meant a generated category
        // reusing a common slug — "achievements", "bosses", "collectibles" —
        // silently won over a locked, user-imported category of the same id.
        // The diff also filters locked ids out of the incoming side, so the
        // review screen never warned about it: a pasted checklist could vanish
        // during a Replace with no mention anywhere. Preserved means preserved.
        for category in preserved {
            let id = (category["id"] as? String) ?? ""
            if let idx = newCats.firstIndex(where: { ($0["id"] as? String) == id }) {
                newCats[idx] = category
            } else {
                newCats.append(category)
            }
        }
        new["categories"] = newCats
        return (try? JSONSerialization.data(withJSONObject: new)) ?? newData
    }

    /// Every category the merge must carry across untouched: Personal Goals
    /// (if it has anything in it) plus everything locked.
    private static func preservedCategories(from oldData: Data) -> [[String: Any]] {
        guard let old = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
              let oldCats = old["categories"] as? [[String: Any]] else { return [] }
        return oldCats.filter { cat in
            let id = cat["id"] as? String
            if (cat["locked"] as? Bool) == true { return true }
            guard id == personalGoalsID else { return false }
            return !((cat["items"] as? [[String: Any]]) ?? []).isEmpty
        }
    }

    private static func mergingGoalsOnly(from oldData: Data, into newData: Data) -> Data {
        guard let old = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
              let oldCats = old["categories"] as? [[String: Any]],
              let goals = oldCats.first(where: { ($0["id"] as? String) == personalGoalsID }),
              !((goals["items"] as? [[String: Any]]) ?? []).isEmpty
        else { return newData }

        guard var new = (try? JSONSerialization.jsonObject(with: newData)) as? [String: Any] else {
            return newData
        }
        var newCats = (new["categories"] as? [[String: Any]]) ?? []
        if !newCats.contains(where: { ($0["id"] as? String) == personalGoalsID }) {
            newCats.append(goals)
            new["categories"] = newCats
        }
        return (try? JSONSerialization.data(withJSONObject: new)) ?? newData
    }
}
