import Foundation

/// Typed view of a tracker schema's JSON (legacy `structuredData` shape,
/// verified against real data). Parsed tolerantly — unknown fields are
/// preserved in the stored JSON and simply not surfaced here.
struct TrackerItemDTO: Identifiable, Hashable, Sendable {
    let id: String
    /// `var` so the repository can overlay a user-chosen name from a
    /// TrackerItemDetail record without rebuilding the whole DTO.
    var name: String
    let itemDescription: String?
    let location: String?
    let missable: Bool
    let hideUntilDiscovered: Bool
    let maxRank: Int?
    let rankNames: [String]?
    /// Optional schema hint: "pips" | "hearts" | "numbered" | "stepper".
    /// Absent in the built-ins, which infer from the data instead.
    let display: String?
    /// Items that must be finished before this one is reachable. Ids, in the
    /// same space as everything else. Lives in the schema JSON — no schema
    /// version needed.
    var requires: [String] = []
    /// Items that finishing THIS one closes off: the questline it ends, the
    /// ending it forecloses, the point of no return.
    var locksOut: [String] = []
    /// How many of this thing there are: 900 koroks, 100 seeds, 60 shrines.
    /// An item with a target is counted rather than ticked — one row instead
    /// of nine hundred, which is the only way those games are trackable at
    /// all. Lives in the schema JSON, so it needs no schema version.
    var countTarget: Int? = nil
    /// The name this arrived with, kept when the user renames it so the merge
    /// engine can still match it against a future generation.
    var sourceName: String? = nil
    /// The user's own note. Distinct from `itemDescription`, which belongs to
    /// whatever generated or supplied the item and may be replaced freely —
    /// this one is theirs and survives every merge.
    var note: String? = nil
    /// What this is worth, where the source has a notion of that.
    /// RetroAchievements scores every achievement, and the importer has been
    /// writing it into `metadata.points` since day one — unread until now,
    /// which is why a 635-point set reported no points at all.
    var points: Int? = nil
    /// RA's badge id for this achievement (`metadata.badge`), when the row
    /// arrived from an imported set. Presence is what turns the row's art on;
    /// schemas without it render exactly as before.
    var badge: String? = nil
    /// Filters a life sim reads by: Spring, Rain, Night, Ocean. Items with
    /// none show under every filter. Its own key, `filters`: generated
    /// trackers already use `tags` for internal labels ("dlc:grimm-troupe",
    /// "part:1") that were never meant to be shown.
    var filters: [String] = []
}

/// One field a category's items carry — a unit's class, level, emblem, or
/// whether it's in the party. Declared in the tracker blob; the values are
/// per playthrough (`TrackerFieldValues`). Four kinds, on purpose.
struct TrackerFieldDTO: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case text, number, choice, multi, toggle

        var label: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .choice: "Choice"
            case .multi: "Several choices"
            case .toggle: "On / off"
            }
        }

        /// Kinds that offer a list of options.
        var hasOptions: Bool { self == .choice || self == .multi }
    }

    var id: String
    var name: String
    var kind: Kind
    /// For `choice`; empty means free entry with your earlier answers offered.
    var options: [String] = []
    /// For `multi`: how many can be picked at once — two skills, four moves.
    /// Nil is no limit.
    var max: Int? = nil

    init(id: String, name: String, kind: Kind, options: [String] = [], max: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = options
        self.max = max
    }

    /// A `multi` value is stored as one text value, joined. One place owns
    /// the separator, as `RunFieldDTO.multiSeparator` does for runs.
    static let multiSeparator = ", "

    static func picks(in text: String?) -> [String] {
        (text ?? "").components(separatedBy: multiSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty, !id.hasPrefix("_"),
              let name = json["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.kind = (json["type"] as? String).flatMap(Kind.init(rawValue:)) ?? .text
        self.options = (json["options"] as? [Any])?.compactMap { $0 as? String } ?? []
        self.max = (json["max"] as? NSNumber)?.intValue
    }

    var json: [String: Any] {
        var out: [String: Any] = ["id": id, "name": name, "type": kind.rawValue]
        if !options.isEmpty { out["options"] = options }
        if kind == .multi, let max, max > 0 { out["max"] = max }
        return out
    }

    /// The field that says a unit is in the party, when the category has one.
    static let partyID = "party"

    /// A start for a party RPG: Class, Level, Weapon, In party — and Emblem
    /// when a sheet offers a list of them. Choices come from `options`
    /// (keyed by field id) when a source has them; otherwise free entry.
    static func rpgDefaults(options: [String: [String]] = [:]) -> [TrackerFieldDTO] {
        var fields: [TrackerFieldDTO] = [
            .init(id: "class", name: "Class", kind: .choice, options: options["class"] ?? []),
            .init(id: "level", name: "Level", kind: .number),
            .init(id: "weapon", name: "Weapon", kind: .choice, options: options["weapon"] ?? []),
        ]
        if let emblems = options["emblem"], !emblems.isEmpty {
            fields.append(.init(id: "emblem", name: "Emblem", kind: .choice, options: emblems))
        }
        fields.append(.init(id: partyID, name: "In party", kind: .toggle))
        return fields
    }
}

struct TrackerCategoryDTO: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let categoryDescription: String?
    let kind: String?          // e.g. "sequence"
    /// `var` for the same reason as `TrackerItemDTO.name` — the overlay.
    var items: [TrackerItemDTO]
    /// As `TrackerItemDTO.sourceName`.
    var sourceName: String? = nil
    /// Planned but not filled in yet — the skeleton a stepped generation
    /// produces before any content exists. Renders as a placeholder with its
    /// own Generate button instead of an empty heading.
    var pending: Bool = false
    /// Roughly how many items are expected, when the plan said so. Sets
    /// expectations before anything is generated ("Bosses, about 18").
    var plannedCount: Int? = nil
    /// The set is too large to be worth listing row by row and will arrive as
    /// a single running total instead (900 Korok Seeds → one 0/900 counter).
    ///
    /// Carried from the plan purely so the placeholder can say so. Without it
    /// the row read "about 900 items" and then produced one, which is a
    /// promise the fill was never going to keep.
    var counted: Bool = false
    /// The RetroAchievements game this category was imported from, stamped at
    /// import. Its presence is what makes this list the authored one.
    var raGameID: Int? = nil
    /// The Steam app this category was imported from — `raGameID`'s twin, and
    /// the id a Steam sync looks the game up by.
    var steamAppID: Int? = nil
    /// A PlayStation trophy list: its NP communication id (`NPWR…`) and the
    /// trophy service it lives on (`trophy` for PS4/PS3/Vita, `trophy2` for PS5).
    var psnTitleID: String? = nil
    var psnService: String? = nil
    /// An Xbox title's achievements, by its decimal title id.
    var xboxTitleID: Int? = nil

    /// Imported from an authored source — RetroAchievements, Steam, PlayStation
    /// or Xbox — rather than generated: never regenerated, kept through Replace.
    var isImportedSet: Bool {
        raGameID != nil || steamAppID != nil || psnTitleID != nil || xboxTitleID != nil
    }
    /// Written by the list parser for a checklist the user pasted in.
    var locked: Bool = false
    /// The pin icon the user chose for this list, on this game. Nil means
    /// read one from the name (`PinStyle`).
    var pinSymbol: String? = nil
    /// …and its color, as one of `PinStyle.colorNames`.
    var pinColor: String? = nil
    /// What each item in this list records beyond its checkbox.
    var fields: [TrackerFieldDTO] = []
    /// How many can be in the party at once, for a roster. A limit to show,
    /// not one to enforce.
    var partySize: Int? = nil
    /// How this list counts toward the game's percentage.
    var progress: ProgressMode = .counts
    /// Ticks here belong to the game, not a playthrough: endings seen, New
    /// Game+ unlocks. They live on the "Across Playthroughs" record.
    var carried: Bool = false
    /// Tick items from run history — "win with every weapon".
    var fromRuns: RunTick? = nil

    enum ProgressMode: String, CaseIterable, Sendable {
        /// An item counts when it's ticked. The default, and every list before
        /// 2026-09-17.
        case counts
        /// Not part of the percentage at all — a list of 900 Koroks you have
        /// no intention of finishing.
        case excluded
        /// A counter or a rank counts for how far along it is.
        case partial

        var label: String {
            switch self {
            case .counts: "Counts"
            case .excluded: "Doesn't count"
            case .partial: "Partial credit"
            }
        }
    }

    /// Which run field names an item, and whether only won runs count.
    struct RunTick: Hashable, Sendable {
        var field: String
        var winsOnly: Bool
    }

    /// A list of characters — rendered with their fields, party and fate.
    var isRoster: Bool { kind == TrackerSchemaJSON.rosterKind }
    /// A list done in order — chapters, a questline — with the next one marked.
    var isSequence: Bool { kind == TrackerSchemaJSON.sequenceKind }
    var partyField: TrackerFieldDTO? {
        fields.first { $0.id == TrackerFieldDTO.partyID && $0.kind == .toggle }
    }

    /// Where this list came from, when the tracker recorded it at creation.
    ///
    /// Deliberately narrow. A generated category records nothing about being
    /// generated — the root's `generatedBy` belongs to the last generation the
    /// whole tracker had, not to any one category, and a merge keeps the
    /// CURRENT root — so inferring "generated" from its absence would be a
    /// guess, and this project does not label user content by inference.
    /// Unlabelled therefore means "nobody wrote it down", not "AI wrote it".
    var provenance: String? {
        if raGameID != nil { return "RetroAchievements" }
        if steamAppID != nil { return "Steam" }
        if psnTitleID != nil { return "PlayStation" }
        if xboxTitleID != nil { return "Xbox" }
        if locked { return "Pasted" }
        return nil
    }
}

// MARK: - Run template (roguelikes / Hades)

struct RunFieldDTO: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let kind: String            // "text" | "select" | "multi" | "number" | "time" | "list"
    let options: [String]
    /// Draw options from a tracker category's items instead of a static list
    /// — the Hades keepsake picker is the Keepsakes category, not a copy of
    /// it. Lives in the schema JSON; absent everywhere it isn't wanted.
    var optionsFrom: String? = nil
    /// With `optionsFrom`: offer only items with recorded progress (checked,
    /// ranked or counted), falling back to the full list when nothing is —
    /// a fresh tracker must not mean an empty picker.
    var onlyUnlocked: Bool = false
    /// With `optionsFrom`: another field's id; options narrow to items whose
    /// `location` matches that field's current value (aspects belong to a
    /// weapon, and the category records which in `location`). Falls back to
    /// the whole category when nothing matches.
    var dependsOn: String? = nil
    /// "start" (default) or "end": where the value is known. You pick a
    /// keepsake before a run; you know where you died after it.
    var phase: String = "start"
    /// For `number` and `time`: which way is better. "high" (score, floor
    /// reached) or "low" (a speedrun time). Nil shows no best.
    var best: String? = nil

    var isEndPhase: Bool { phase == "end" }
    /// A list that fills up while the run is live — boons, relics, jokers.
    var isRunList: Bool { kind == "list" }
    var isNumeric: Bool { kind == "number" || kind == "time" }
    /// Multi-valued fields store their value comma-joined; one place owns
    /// the separator so entry and analytics can't drift apart.
    static let multiSeparator = ", "

    var json: [String: Any] {
        var out: [String: Any] = ["id": id, "label": label, "type": kind]
        if !options.isEmpty { out["options"] = options }
        if let optionsFrom { out["optionsFrom"] = optionsFrom }
        if onlyUnlocked { out["onlyUnlocked"] = true }
        if let dependsOn { out["dependsOn"] = dependsOn }
        if phase != "start" { out["phase"] = phase }
        if let best { out["best"] = best }
        return out
    }
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
                options: (f["options"] as? [Any])?.compactMap { $0 as? String } ?? [],
                optionsFrom: f["optionsFrom"] as? String,
                onlyUnlocked: (f["onlyUnlocked"] as? Bool) ?? false,
                dependsOn: f["dependsOn"] as? String,
                // A run list is filled during the run whatever the file says.
                phase: (f["type"] as? String) == "list" ? "during" : ((f["phase"] as? String) ?? "start"),
                best: f["best"] as? String
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
                    requires: (item["requires"] as? [Any])?.compactMap { $0 as? String } ?? [],
                    locksOut: (item["locksOut"] as? [Any])?.compactMap { $0 as? String } ?? [],
                    countTarget: (item["countTarget"] as? NSNumber)?.intValue,
                    sourceName: item["sourceName"] as? String,
                    note: item["note"] as? String,
                    points: ((item["metadata"] as? [String: Any])?["points"] as? NSNumber)?.intValue,
                    badge: (item["metadata"] as? [String: Any])?["badge"] as? String,
                    filters: (item[filtersKey] as? [Any])?.compactMap { $0 as? String } ?? []
                )
            }
            return TrackerCategoryDTO(
                id: id,
                name: name,
                categoryDescription: raw["description"] as? String,
                kind: raw["type"] as? String,
                items: items,
                sourceName: raw["sourceName"] as? String,
                pending: (raw["pending"] as? Bool) ?? false,
                plannedCount: (raw["plannedCount"] as? NSNumber)?.intValue,
                counted: (raw["counted"] as? Bool) ?? false,
                raGameID: (raw["raGameID"] as? NSNumber)?.intValue,
                steamAppID: (raw[steamAppIDKey] as? NSNumber)?.intValue,
                psnTitleID: (raw[psnTitleIDKey] as? String).flatMap { $0.isEmpty ? nil : $0 },
                psnService: raw[psnServiceKey] as? String,
                xboxTitleID: (raw[xboxTitleIDKey] as? NSNumber)?.intValue,
                locked: (raw["locked"] as? Bool) ?? false,
                pinSymbol: raw[pinSymbolKey] as? String,
                pinColor: raw[pinColorKey] as? String,
                fields: (raw[fieldsKey] as? [[String: Any]])?.compactMap(TrackerFieldDTO.init(json:)) ?? [],
                partySize: (raw[partySizeKey] as? NSNumber)?.intValue,
                progress: (raw[progressKey] as? String).flatMap(TrackerCategoryDTO.ProgressMode.init(rawValue:)) ?? .counts,
                carried: (raw[carriedKey] as? Bool) ?? false,
                fromRuns: (raw[fromRunsKey] as? [String: Any]).flatMap { rule in
                    (rule["field"] as? String).map {
                        TrackerCategoryDTO.RunTick(field: $0, winsOnly: (rule["winsOnly"] as? Bool) ?? false)
                    }
                }
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

    /// Add an empty, planned category — the unit a stepped generation works
    /// in. Marked `pending` so the tracker shows it as a placeholder to fill
    /// rather than an empty heading, and carries the expected size when known.
    ///
    /// Creates the schema if the game has none, so planning a tracker is a
    /// legitimate way to START one rather than something only available after
    /// a generation.
    static func addingCategory(named name: String, id: String? = nil,
                               plannedCount: Int? = nil, counted: Bool = false,
                               kind: String? = nil, fields: [TrackerFieldDTO] = [],
                               partySize: Int? = nil,
                               to data: Data) -> Data? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if root["schemaVersion"] == nil { root["schemaVersion"] = 1 }
        var cats = (root["categories"] as? [[String: Any]]) ?? []
        let categoryID = id ?? "cat-\(UUID().uuidString.prefix(8))"
        guard !cats.contains(where: { ($0["id"] as? String) == categoryID }) else { return nil }
        var category: [String: Any] = [
            "id": categoryID, "name": trimmed, "items": [], "pending": true,
        ]
        if let plannedCount, plannedCount > 0 { category["plannedCount"] = plannedCount }
        if counted { category["counted"] = true }
        // A roster or sequence the planner proposed arrives as one, fields and
        // all, so filling it keeps the shape (TrackerMerge carries both).
        if let kind, [rosterKind, sequenceKind].contains(kind) { category["type"] = kind }
        if !fields.isEmpty { category[fieldsKey] = fields.map(\.json) }
        if let partySize, partySize > 0 { category[partySizeKey] = partySize }
        cats.append(category)
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Reorder the categories to the given ids, keeping anything unnamed in
    /// its existing place at the end. Ids that don't exist are ignored.
    static func reordering(to ids: [String], in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cats = root["categories"] as? [[String: Any]] else { return nil }
        var remaining = cats
        var ordered: [[String: Any]] = []
        for id in ids {
            if let index = remaining.firstIndex(where: { ($0["id"] as? String) == id }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        ordered.append(contentsOf: remaining)
        root["categories"] = ordered
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// Float filled categories above planned ones, each group keeping its own
    /// order.
    ///
    /// A planned category is scaffolding — something still to do — and it
    /// belongs under the tracker rather than in the middle of it. Applied to
    /// the STORED order rather than at render time, so there is exactly one
    /// order: what you see is what a manual move then acts on, and it is the
    /// same on the other device.
    static func sinkingPendingCategories(in data: Data) -> Data? {
        let cats = categories(from: data)
        guard cats.contains(where: \.pending) else { return nil }
        let ordered = cats.filter { !$0.pending }.map(\.id) + cats.filter(\.pending).map(\.id)
        return reordering(to: ordered, in: data)
    }

    /// Clear the planned flag once a category has real content.
    static func markingFilled(categoryID: String, in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let idx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }
        var category = cats[idx]
        category.removeValue(forKey: "pending")
        category.removeValue(forKey: "plannedCount")
        category.removeValue(forKey: "counted")
        cats[idx] = category
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }

    /// The category key a Steam import stamps, beside `raGameID`.
    static let steamAppIDKey = "steamAppID"

    /// The Steam app this tracker's achievements came from, if any. Only the
    /// category stamp: a Steam import is never the whole tracker's root.
    static func steamAppID(in data: Data) -> Int? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for category in (root["categories"] as? [[String: Any]]) ?? [] {
            if let id = (category[steamAppIDKey] as? NSNumber)?.intValue, id > 0 { return id }
        }
        return nil
    }

    static let psnTitleIDKey = "psnTitleID"
    static let psnServiceKey = "psnService"
    static let xboxTitleIDKey = "xboxTitleID"

    /// The PlayStation trophy list this tracker's trophies came from, if any.
    static func playStationTitle(in data: Data) -> (id: String, service: String)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for category in (root["categories"] as? [[String: Any]]) ?? [] {
            if let id = category[psnTitleIDKey] as? String, !id.isEmpty {
                return (id, (category[psnServiceKey] as? String) ?? "trophy2")
            }
        }
        return nil
    }

    /// The Xbox title this tracker's achievements came from, if any.
    static func xboxTitleID(in data: Data) -> Int? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for category in (root["categories"] as? [[String: Any]]) ?? [] {
            if let id = (category[xboxTitleIDKey] as? NSNumber)?.intValue, id > 0 { return id }
        }
        return nil
    }

    /// The RetroAchievements game id this tracker was imported from, if any.
    ///
    /// Read back out of `sources` rather than stored in a new field: the
    /// importer already writes the RA game URL there, so the id is available
    /// for free and syncing needs no schema version.
    static func retroAchievementsGameID(in data: Data) -> Int? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        // The category stamp first. Merging an import into an existing tracker
        // keeps the CURRENT root — so its `sources` never mention RA — while
        // the category itself is copied across whole.
        for category in (root["categories"] as? [[String: Any]]) ?? [] {
            if let id = (category["raGameID"] as? NSNumber)?.intValue, id > 0 { return id }
        }
        guard let sources = root["sources"] as? [[String: Any]] else { return nil }
        for source in sources {
            guard (source["type"] as? String) == "retroachievements",
                  let url = source["url"] as? String,
                  let last = url.split(separator: "/").last,
                  let id = Int(last) else { continue }
            return id
        }
        return nil
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
    /// Replace the run template's fields, keeping its outcomes. A field's
    /// values stay on the runs that recorded them, so removing one and adding
    /// it back by the same id brings its history back.
    static func settingRunFields(_ fields: [RunFieldDTO], in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var template = root["runTemplate"] as? [String: Any] else { return nil }
        template["fields"] = fields.map(\.json)
        root["runTemplate"] = template
        return try? JSONSerialization.data(withJSONObject: root)
    }

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

    static let pinSymbolKey = "pinSymbol"
    static let fieldsKey = "fields"
    static let partySizeKey = "partySize"
    static let rosterKind = "roster"
    static let progressKey = "progress"
    static let filtersKey = "filters"
    static let carriedKey = "carried"
    static let fromRunsKey = "fromRuns"
    /// The state row a playthrough's focus rides on. Item ids never start
    /// with an underscore (`TrackerFieldDTO` refuses them for fields; the
    /// generator and every importer write slugs).
    static let focusItemID = "_focus"

    /// Set how a list counts, whether it's shared across playthroughs, and
    /// whether runs tick it.
    static func settingListRules(categoryID: String, progress: TrackerCategoryDTO.ProgressMode,
                                 carried: Bool, fromRuns: TrackerCategoryDTO.RunTick?,
                                 in data: Data) -> Data? {
        editingCategory(categoryID, in: data) { category in
            if progress == .counts { category.removeValue(forKey: progressKey) }
            else { category[progressKey] = progress.rawValue }
            if carried { category[carriedKey] = true } else { category.removeValue(forKey: carriedKey) }
            if let fromRuns {
                category[fromRunsKey] = ["field": fromRuns.field, "winsOnly": fromRuns.winsOnly]
            } else {
                category.removeValue(forKey: fromRunsKey)
            }
        }
    }
    static let sequenceKind = "sequence"

    /// Set how a list reads — a roster of characters, a sequence done in
    /// order, or an ordinary checklist (nil) — and, for a roster, its party
    /// size. The type is the category's `type` key, which every tracker
    /// already carries and nothing read until now.
    static func settingListKind(categoryID: String, kind: String?, partySize: Int?,
                                in data: Data) -> Data? {
        editingCategory(categoryID, in: data) { category in
            if let kind, !kind.isEmpty { category["type"] = kind } else { category["type"] = "checklist" }
            if let partySize, partySize > 0 { category[partySizeKey] = partySize }
            else { category.removeValue(forKey: partySizeKey) }
        }
    }

    /// Replace a category's field declarations. Values already recorded for a
    /// field that is removed stay on the state rows, so adding it back finds
    /// them.
    static func settingFields(_ fields: [TrackerFieldDTO], categoryID: String,
                              in data: Data) -> Data? {
        editingCategory(categoryID, in: data) { category in
            if fields.isEmpty { category.removeValue(forKey: fieldsKey) }
            else { category[fieldsKey] = fields.map(\.json) }
        }
    }

    /// A new item at the end of a category — a unit the list didn't have.
    static func addingItem(named name: String, id: String, categoryID: String,
                           in data: Data) -> Data? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return editingCategory(categoryID, in: data) { category in
            var items = (category["items"] as? [[String: Any]]) ?? []
            items.append(["id": id, "name": trimmed])
            category["items"] = items
            category["pending"] = false
        }
    }

    private static func editingCategory(_ categoryID: String, in data: Data,
                                        _ change: (inout [String: Any]) -> Void) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let cIdx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }
        var category = cats[cIdx]
        change(&category)
        cats[cIdx] = category
        root["categories"] = cats
        return try? JSONSerialization.data(withJSONObject: root)
    }
    static let pinColorKey = "pinColor"

    /// The pin icon and color the user chose for a category. `nil` puts that
    /// half back to automatic.
    ///
    /// In the blob, beside the category's name, because that is where a
    /// renamed category already lives — so an icon syncs exactly as well as
    /// the name it belongs to, with no schema version. It survives a
    /// regeneration because `TrackerMerge.carryingUserEdits` carries both keys
    /// across the way it carries a chosen name.
    static func settingPinStyle(categoryID: String, symbol: String?, color: String?,
                                in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let cIdx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID })
        else { return nil }
        var category = cats[cIdx]
        if let symbol, !symbol.isEmpty {
            category[pinSymbolKey] = symbol
        } else {
            category.removeValue(forKey: pinSymbolKey)
        }
        if let color, !color.isEmpty {
            category[pinColorKey] = color
        } else {
            category.removeValue(forKey: pinColorKey)
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
                            note: String? = nil, countTarget: Int? = nil,
                            filters: [String]? = nil,
                            in data: Data) -> Data? {
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
        if let filters {
            var seen = Set<String>()
            let cleaned = filters.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            if cleaned.isEmpty { item.removeValue(forKey: filtersKey) } else { item[filtersKey] = cleaned }
        }
        if let countTarget {
            // Zero clears it: the row goes back to a plain checkbox rather
            // than a counter that can never be finished.
            if countTarget > 0 { item["countTarget"] = countTarget }
            else { item.removeValue(forKey: "countTarget") }
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

    /// Categories that came from an authored external source rather than from
    /// the generator — an import from RetroAchievements, Steam, PlayStation or Xbox.
    ///
    /// These are not regenerable content. The achievement list is the real one
    /// RA publishes, and the category carries the `raGameID` stamp that every
    /// later sync looks the game up by, so letting a full Replace drop it would
    /// throw away both the list and the link that could restore it.
    ///
    /// Deliberately NOT expressed as `locked`. Locking would preserve it here
    /// too, but `replacingCategories` refuses to touch a locked id, and RA's own
    /// refresh is exactly that call — a scoped replace of "retroachievements".
    /// Locking the category would protect it from regeneration by also breaking
    /// re-import, which is the one operation that is supposed to replace it.
    static func importedSourceCategoryIDs(in data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = root["categories"] as? [[String: Any]] else { return [] }
        return Set(cats.compactMap { cat in
            let ra = (cat["raGameID"] as? NSNumber)?.intValue ?? 0
            let steam = (cat[steamAppIDKey] as? NSNumber)?.intValue ?? 0
            let xbox = (cat[xboxTitleIDKey] as? NSNumber)?.intValue ?? 0
            let psn = (cat[psnTitleIDKey] as? String) ?? ""
            guard ra > 0 || steam > 0 || xbox > 0 || !psn.isEmpty else { return nil }
            return cat["id"] as? String
        })
    }

    // MARK: Applicability

    /// What this tracker is FOR — the platform, edition, and DLC/patch scope
    /// its numbers are true of. A tracker for the wrong edition is the
    /// fastest way to make "the numbers are true" false, and until now the
    /// tracker had nowhere to say which edition it meant. Root-level JSON
    /// keys, so no schema version.
    struct Applicability: Equatable {
        var platform: String = ""
        var edition: String = ""
        var notes: String = ""

        var isEmpty: Bool { platform.isEmpty && edition.isEmpty && notes.isEmpty }

        /// "Switch · Definitive Edition · post-1.5, no DLC"
        var summary: String {
            [platform, edition, notes].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    static func applicability(in data: Data) -> Applicability {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["applicability"] as? [String: Any] else { return Applicability() }
        return Applicability(
            platform: (raw["platform"] as? String) ?? "",
            edition: (raw["edition"] as? String) ?? "",
            notes: (raw["notes"] as? String) ?? "")
    }

    static func settingApplicability(_ value: Applicability, in data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if value.isEmpty {
            root.removeValue(forKey: "applicability")
        } else {
            var raw: [String: Any] = [:]
            if !value.platform.isEmpty { raw["platform"] = value.platform }
            if !value.edition.isEmpty { raw["edition"] = value.edition }
            if !value.notes.isEmpty { raw["notes"] = value.notes }
            root["applicability"] = raw
        }
        return try? JSONSerialization.data(withJSONObject: root)
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
        //
        // Every collision, not just the first: an unsanitized payload can
        // carry the same id twice, and replacing one occurrence brought the
        // "replaced" generated category straight back as a duplicate. And if
        // two PRESERVED categories somehow share an id (corrupt synced data),
        // the second folds its items into the first instead of silently
        // overwriting it — both are the user's own content.
        var placedByID: [String: Int] = [:]
        for category in preserved {
            let id = (category["id"] as? String) ?? ""
            // A plan is kept only while the new tracker hasn't already got that
            // list — otherwise Replace would leave "Bosses" twice. Its own id
            // doesn't count: an additive merge can already carry the plan.
            if (category["pending"] as? Bool) == true {
                let key = TrackerMerge.matchKey((category["name"] as? String) ?? "")
                if newCats.contains(where: { ($0["id"] as? String) != id
                        && TrackerMerge.matchKey(($0["name"] as? String) ?? "") == key }) { continue }
            }
            if let prior = placedByID[id] {
                var target = newCats[prior]
                var items = (target["items"] as? [[String: Any]]) ?? []
                items += (category["items"] as? [[String: Any]]) ?? []
                // Fold, then dedup by id — concatenating without it could
                // reintroduce duplicate item ids after the incoming payload
                // had already been sanitized.
                var seenIDs = Set<String>()
                target["items"] = items.filter { item in
                    guard let itemID = item["id"] as? String, !itemID.isEmpty else { return true }
                    return seenIDs.insert(itemID).inserted
                }
                newCats[prior] = target
                continue
            }
            if let idx = newCats.firstIndex(where: { ($0["id"] as? String) == id }) {
                newCats[idx] = category
                var i = newCats.count - 1
                while i > idx {
                    if (newCats[i]["id"] as? String) == id { newCats.remove(at: i) }
                    i -= 1
                }
                placedByID[id] = idx
            } else {
                newCats.append(category)
                placedByID[id] = newCats.count - 1
            }
        }
        new["categories"] = newCats
        return (try? JSONSerialization.data(withJSONObject: new)) ?? newData
    }

    /// Every category the merge must carry across untouched: Personal Goals
    /// (if it has anything in it), everything locked, everything imported from
    /// an authored source, and every plan that hasn't been filled yet.
    private static func preservedCategories(from oldData: Data) -> [[String: Any]] {
        guard let old = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
              let oldCats = old["categories"] as? [[String: Any]] else { return [] }
        let imported = importedSourceCategoryIDs(in: oldData)
        return oldCats.filter { cat in
            let id = cat["id"] as? String
            if (cat["locked"] as? Bool) == true { return true }
            if let id, imported.contains(id) { return true }
            // A plan is the user's intention, not generated content. Codex,
            // 09-15: a Replace dropped plans without a word, because the loss
            // warning counts items and a plan has none.
            if (cat["pending"] as? Bool) == true,
               ((cat["items"] as? [[String: Any]]) ?? []).isEmpty { return true }
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
