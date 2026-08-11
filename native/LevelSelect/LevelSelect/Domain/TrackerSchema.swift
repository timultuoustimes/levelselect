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
}

struct TrackerCategoryDTO: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let categoryDescription: String?
    let kind: String?          // e.g. "sequence"
    let items: [TrackerItemDTO]
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
        let outcomes: [RunOutcomeDTO] = ((raw["outcomes"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let id = o["id"] as? String else { return nil }
            return RunOutcomeDTO(
                id: id,
                label: (o["label"] as? String) ?? id.capitalized,
                result: RunOutcome(rawValue: (o["result"] as? String) ?? "") ?? .neutral
            )
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
                    rankNames: (item["rankNames"] as? [Any])?.compactMap { $0 as? String }
                )
            }
            return TrackerCategoryDTO(
                id: id,
                name: name,
                categoryDescription: raw["description"] as? String,
                kind: raw["type"] as? String,
                items: items
            )
        }
    }

    /// Append a Personal Goals item, preserving all unknown fields in the JSON.
    /// Creates the Personal Goals category if missing. Returns updated data.
    static func addingGoal(named goalName: String, to data: Data) -> Data? {
        var root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if root["schemaVersion"] == nil { root["schemaVersion"] = 1 }
        var cats = (root["categories"] as? [[String: Any]]) ?? []
        let newItem: [String: Any] = ["id": "goal-\(UUID().uuidString.prefix(8))", "name": goalName]

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
    static func emptySchema() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": []])) ?? Data()
    }

    /// Carry the user's Personal Goals category from an old schema into a
    /// newly generated one (regeneration must never eat user-created goals).
    static func mergingPersonalGoals(from oldData: Data, into newData: Data) -> Data {
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
