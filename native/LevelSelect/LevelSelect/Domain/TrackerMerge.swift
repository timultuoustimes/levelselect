import Foundation

// MARK: - Diff model

/// One item that exists on both sides but under a different id — the case that
/// silently costs you progress, since `TrackerStateRecord` is keyed by item id.
struct TrackerItemMatch: Hashable, Sendable {
    let current: TrackerItemDTO
    let incoming: TrackerItemDTO
}

struct TrackerCategoryDiff: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// The incoming schema introduces this category; nothing here today.
    let isNewCategory: Bool
    /// In the incoming schema, not in the current one.
    let added: [TrackerItemDTO]
    /// In the current schema, absent from the incoming one — these disappear
    /// under Replace.
    let removed: [TrackerItemDTO]
    /// Same item, different id. Survives Replace as *content* but loses any
    /// progress recorded against the old id.
    let renamed: [TrackerItemMatch]
    /// Matched on the same id, so progress carries across untouched.
    let unchangedCount: Int

    var hasChanges: Bool { !added.isEmpty || !removed.isEmpty || !renamed.isEmpty }
}

struct TrackerDiff: Hashable, Sendable {
    let categories: [TrackerCategoryDiff]
    /// Items carrying progress today that a Replace would orphan *if nothing
    /// intervened* — either the item is gone, or it came back under a new id.
    ///
    /// The two halves have very different fates once the store gets involved:
    /// the renamed half is **recoverable**, because `Repository` rewrites the
    /// state record's `itemID` to follow the rename, and only the genuinely
    /// removed half is really lost. This engine deliberately doesn't know
    /// about that — it reports the raw exposure, and the caller that performs
    /// the migration is the one that can say what actually went.
    let strandedByReplace: [TrackerItemDTO]

    var added: [TrackerItemDTO] { categories.flatMap(\.added) }
    var removed: [TrackerItemDTO] { categories.flatMap(\.removed) }
    var renamed: [TrackerItemMatch] { categories.flatMap(\.renamed) }
    var unchangedCount: Int { categories.reduce(0) { $0 + $1.unchangedCount } }
    var newCategories: [TrackerCategoryDiff] { categories.filter(\.isNewCategory) }

    /// Nothing would change either way — worth telling the user plainly rather
    /// than showing them an empty review screen.
    var isEmpty: Bool { !categories.contains(where: \.hasChanges) }
}

/// How an incoming schema should be folded into the stored one.
enum TrackerMergeMode: Hashable, Sendable {
    /// Incoming wins outright. Today's regeneration behaviour — Personal Goals
    /// are still carried across, everything else is replaced.
    case replace
    /// Keep everything already there and append everything new. Never removes,
    /// never renames, so no progress can be lost.
    case addAll
    /// Append only the incoming items the user ticked. Ids are incoming item
    /// ids, as reported by `TrackerDiff.added`.
    case add(itemIDs: Set<String>)
    /// Replace the contents of specific categories and leave every other
    /// category exactly as it is. Ids are CURRENT category ids.
    ///
    /// "This category is wrong, do it again" is a much smaller ask than
    /// regenerating a whole tracker, and it is what per-category generation
    /// needs: a stepped run fills one category at a time, and each step must
    /// not disturb the ones already accepted.
    case replaceCategories(ids: Set<String>)
}

// MARK: - Engine

/// Compares a stored tracker schema against an incoming one and folds them
/// together on the user's terms.
///
/// This exists because applying a generated schema was previously all-or-
/// nothing: `setGeneratedSchema` overwrites `jsonData` wholesale, while
/// progress lives in `TrackerStateRecord` keyed by *item id*. AI generation is
/// nondeterministic, so a regeneration routinely re-slugs ids — and every
/// checkmark on a re-slugged item stops counting, with no warning and nothing
/// on screen to explain where the progress went.
///
/// Everything here is pure: schema JSON in, schema JSON out. Progress ids are
/// passed in rather than read from the store, so this stays testable and free
/// of SwiftData.
enum TrackerMerge {

    /// Match key for a name or id. Case-, diacritic- and punctuation-
    /// insensitive, so `"Boss: False Knight"`, `"boss-false-knight"` and
    /// `"false knight"` all collapse together. This is what lets a
    /// regeneration that renamed every id still be recognised as the same
    /// content rather than reported as a wholesale replacement.
    static func matchKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Ingest sanitation

    /// Normalize an untrusted incoming schema ONCE, before any diff, merge or
    /// install sees it.
    ///
    /// The AI generator's contract requires ids to be strings — not to be
    /// unique — and the lenient parser doesn't check either. Duplicate item
    /// ids share one state record (ticking either row ticks both) and
    /// duplicate category ids poison diff matching. So duplicates are folded
    /// by ID — and by ID ONLY. Display names are deliberately NOT identity:
    /// the paste parser mints distinct ids for repeated names ("Chest" at
    /// three locations), and the shipped built-ins carry six distinct rows
    /// all named "Aspect of Zagreus". Round 3 caught this sanitizer treating
    /// name equality as identity and silently deleting exactly that data
    /// after the preview had promised it — a duplicate the user can see and
    /// delete beats an item the code silently decided didn't exist.
    ///
    /// Categories sharing an id are folded into the first occurrence (their
    /// items concatenated, then id-deduped); items repeating an id within a
    /// category keep the first occurrence. Operates on raw dictionaries so
    /// unknown fields survive, like every other transform here. Idempotent;
    /// non-schema data passes through untouched.
    static func deduplicated(_ data: Data) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rawCats = root["categories"] as? [[String: Any]]
        else { return data }

        var cats: [[String: Any]] = []
        var indexByID: [String: Int] = [:]
        for cat in rawCats {
            let id = (cat["id"] as? String) ?? ""
            if !id.isEmpty, let hit = indexByID[id] {
                var target = cats[hit]
                var items = (target["items"] as? [[String: Any]]) ?? []
                items += (cat["items"] as? [[String: Any]]) ?? []
                target["items"] = items
                cats[hit] = target
            } else {
                cats.append(cat)
                if !id.isEmpty { indexByID[id] = cats.count - 1 }
            }
        }

        // One set across the WHOLE schema, not one per category. Progress is
        // stored per item id on the playthrough, not per (category, item) —
        // so the same id in two categories is one shared TrackerStateRecord,
        // and ticking either row ticks both. Deleting one category then
        // tombstones that shared state and unticks the survivor. Per-category
        // dedup let exactly the collision it exists to prevent through the
        // front door.
        var seenIDs = Set<String>()
        for (idx, cat) in cats.enumerated() {
            var kept: [[String: Any]] = []
            for item in (cat["items"] as? [[String: Any]]) ?? [] {
                let id = (item["id"] as? String) ?? ""
                if !id.isEmpty, seenIDs.contains(id) { continue }
                if !id.isEmpty { seenIDs.insert(id) }
                kept.append(item)
            }
            var next = cat
            next["items"] = kept
            cats[idx] = next
        }

        root["categories"] = cats
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }

    // MARK: Diff

    static func diff(current: Data, incoming: Data,
                     progressIDs: Set<String> = []) -> TrackerDiff {
        // Personal Goals and locked categories are the user's own content and
        // are preserved by every mode, so they're never part of the comparison
        // — reporting them as "removed" would be both wrong and alarming.
        let locked = TrackerSchemaJSON.lockedCategoryIDs(in: current)
        let cur = TrackerSchemaJSON.categories(from: current)
            .filter { $0.id != TrackerSchemaJSON.personalGoalsID && !locked.contains($0.id) }
        let inc = TrackerSchemaJSON.categories(from: incoming)
            .filter { $0.id != TrackerSchemaJSON.personalGoalsID && !locked.contains($0.id) }

        var diffs: [TrackerCategoryDiff] = []
        var matchedCurrent = Set<String>()
        // Current ids that some incoming category claims EXACTLY. A name
        // match may not steal one of these: with current "bosses" and
        // incoming [b1 named "Bosses", "bosses" renamed], the name matcher
        // running first used to consume the current category the id matcher
        // was about to claim, and the result depended on incoming order.
        let reservedIDs = Set(inc.map(\.id)).intersection(cur.map(\.id))

        for incCat in inc {
            // Id, then the displayed name, then the name it *arrived* with —
            // the last one is what stops a user-renamed category ("Stages" →
            // "Achievements") being imported all over again as a duplicate the
            // next time the generator returns the original name. A current
            // category can be matched at most ONCE — on the id branch too:
            // round 3 showed duplicate incoming ids both taking the
            // unguarded id branch and double-claiming one current category.
            let match = cur.first { !matchedCurrent.contains($0.id) && $0.id == incCat.id }
                ?? cur.first {
                    !matchedCurrent.contains($0.id) && !reservedIDs.contains($0.id)
                        && matchKey($0.name) == matchKey(incCat.name)
                }
                ?? cur.first { source in
                    guard !matchedCurrent.contains(source.id),
                          !reservedIDs.contains(source.id),
                          let original = source.sourceName else { return false }
                    return matchKey(original) == matchKey(incCat.name)
                }
            guard let curCat = match else {
                diffs.append(TrackerCategoryDiff(
                    id: incCat.id, name: incCat.name, isNewCategory: true,
                    added: incCat.items, removed: [], renamed: [], unchangedCount: 0))
                continue
            }
            matchedCurrent.insert(curCat.id)
            diffs.append(categoryDiff(current: curCat, incoming: incCat))
        }

        // Categories that exist today and the incoming schema never mentions:
        // under Replace every item in them vanishes.
        for curCat in cur where !matchedCurrent.contains(curCat.id) {
            diffs.append(TrackerCategoryDiff(
                id: curCat.id, name: curCat.name, isNewCategory: false,
                added: [], removed: curCat.items, renamed: [], unchangedCount: 0))
        }

        // Progress strands two ways, and the second is the non-obvious one:
        // the item is still there, but under a new id the state records can't
        // find.
        let stranded = diffs.flatMap { d in
            d.removed.filter { progressIDs.contains($0.id) }
                + d.renamed.map(\.current).filter { progressIDs.contains($0.id) }
        }

        return TrackerDiff(categories: diffs, strandedByReplace: stranded)
    }

    private static func categoryDiff(current: TrackerCategoryDTO,
                                     incoming: TrackerCategoryDTO) -> TrackerCategoryDiff {
        let curByID = Dictionary(current.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Both the displayed name and the name it arrived with, so renaming an
        // item doesn't make the next generation treat it as new.
        var byName: [String: TrackerItemDTO] = [:]
        for item in current.items {
            byName[matchKey(item.name)] = byName[matchKey(item.name)] ?? item
            if let original = item.sourceName {
                byName[matchKey(original)] = byName[matchKey(original)] ?? item
            }
        }
        let curByName = byName

        var added: [TrackerItemDTO] = []
        var renamed: [TrackerItemMatch] = []
        var unchanged = 0
        var consumed = Set<String>()

        for item in incoming.items {
            if let hit = curByID[item.id] {
                consumed.insert(hit.id)
                unchanged += 1
            } else if let hit = curByName[matchKey(item.name)], !consumed.contains(hit.id) {
                consumed.insert(hit.id)
                renamed.append(TrackerItemMatch(current: hit, incoming: item))
            } else {
                added.append(item)
            }
        }

        let removed = current.items.filter { !consumed.contains($0.id) }

        return TrackerCategoryDiff(
            id: current.id, name: current.name, isNewCategory: false,
            added: added, removed: removed, renamed: renamed, unchangedCount: unchanged)
    }

    // MARK: Merge

    static func merged(current: Data, incoming: Data, mode: TrackerMergeMode) -> Data {
        switch mode {
        case .replace:
            let replaced = TrackerSchemaJSON.mergingPersonalGoals(from: current, into: incoming)
            // Replace throws away the generator's content, not the user's.
            return carryingUserEdits(from: current, into: replaced)
        case .addAll:
            return additive(current: current, incoming: incoming, accepting: nil)
        case .add(let ids):
            guard !ids.isEmpty else { return current }
            return additive(current: current, incoming: incoming, accepting: ids)
        case .replaceCategories(let ids):
            guard !ids.isEmpty else { return current }
            return replacingCategories(ids: ids, current: current, incoming: incoming)
        }
    }

    /// Swap the items of named categories for the incoming ones, then carry
    /// the user's own edits back over exactly as a full Replace does.
    ///
    /// Built as "swap, then reuse the existing carry" rather than a second
    /// carry implementation: the untouched categories are identical on both
    /// sides, so carrying across them is a no-op, and the note/rename rules
    /// that took three review rounds to get right stay in one place.
    private static func replacingCategories(ids: Set<String>, current: Data,
                                            incoming: Data) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let incRoot = (try? JSONSerialization.jsonObject(with: incoming)) as? [String: Any]
        else { return current }
        let incCats = (incRoot["categories"] as? [[String: Any]]) ?? []
        // A locked category, and Personal Goals, are the user's own content;
        // regenerating "everything in this category" must still not mean them.
        let locked = TrackerSchemaJSON.lockedCategoryIDs(in: current)

        for (index, category) in cats.enumerated() {
            guard let id = category["id"] as? String, ids.contains(id),
                  !locked.contains(id), id != TrackerSchemaJSON.personalGoalsID
            else { continue }
            let name = (category["name"] as? String) ?? ""
            let source = category["sourceName"] as? String
            let match = incCats.first { ($0["id"] as? String) == id }
                ?? incCats.first { matchKey(($0["name"] as? String) ?? "") == matchKey(name) }
                ?? incCats.first { inc in
                    guard let source else { return false }
                    return matchKey((inc["name"] as? String) ?? "") == matchKey(source)
                }
            guard let match, let items = match["items"] as? [[String: Any]] else { continue }
            // Start from the INCOMING category, not the existing one. Keeping
            // the old dictionary and swapping only `items` silently retained
            // every category-level field of the previous import — including
            // `raGameID`, so correcting a wrong RetroAchievements match left
            // sync still asking about the game you replaced, and reporting all
            // the new achievements as unknown.
            //
            // The user's own choices are then restored on top: the id is
            // local (a planned category's id is minted on-device and can never
            // appear in a payload), the name may have been renamed by hand,
            // and `locked`/`sourceName` are the anchors that keep future
            // merges matching.
            var next = match
            next["id"] = category["id"]
            if let name = category["name"] { next["name"] = name }
            if let source = category["sourceName"] { next["sourceName"] = source }
            if let locked = category["locked"] { next["locked"] = locked }
            next["items"] = items
            cats[index] = next
        }
        root["categories"] = cats
        let swapped = (try? JSONSerialization.data(withJSONObject: root)) ?? current
        return carryingUserEdits(from: current, into: swapped)
    }

    /// Re-apply the user's own edits on top of a replaced schema.
    ///
    /// Replace is meant to discard the *generator's* content, not the user's.
    /// Two things carry across for anything that still matches: a note they
    /// wrote, and a name they chose (with its `sourceName` anchor, so matching
    /// keeps working next time). Without this, writing a note on a generated
    /// item and then regenerating would silently lose it — which is precisely
    /// the failure mode the merge work exists to end.
    private static func carryingUserEdits(from current: Data, into replaced: Data) -> Data {
        guard let cur = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any],
              let curCats = cur["categories"] as? [[String: Any]],
              var root = (try? JSONSerialization.jsonObject(with: replaced)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]]
        else { return replaced }

        // Keyed PER CATEGORY, not globally.
        //
        // A single global map meant two categories each containing an item
        // called "Complete" or "Boss 1" would donate one item's private note
        // and chosen name to the other — a note written under one heading
        // silently reappearing under a different one. Scoping the lookup to the
        // category makes a collision only possible between items that really
        // are in the same list.
        //
        // Ambiguity is inert, not arbitrary: when two DIFFERENT categories
        // (or two different items within one) collapse to the same normalized
        // name, that name key is removed rather than left pointing at
        // whichever registered first. A note carried to the wrong similarly-
        // named place is worse than a note that stays put; id matches still
        // work, and only the genuinely ambiguous name is refused.
        var byCategory: [String: [String: [String: Any]]] = [:]
        var ambiguousCategoryKeys = Set<String>()
        for category in curCats {
            let catID = (category["id"] as? String) ?? ""
            var byKey: [String: [String: Any]] = [:]
            var ambiguousItemKeys = Set<String>()
            for item in (category["items"] as? [[String: Any]]) ?? [] {
                if let id = item["id"] as? String {
                    byKey["id:\(id)"] = byKey["id:\(id)"] ?? item
                }
                let nameKeys = [item["name"], item["sourceName"]]
                    .compactMap { ($0 as? String).map { "name:\(matchKey($0))" } }
                for key in Set(nameKeys) {
                    if let existing = byKey[key],
                       (existing["id"] as? String) != (item["id"] as? String) {
                        ambiguousItemKeys.insert(key)
                    } else {
                        byKey[key] = item
                    }
                }
            }
            for key in ambiguousItemKeys { byKey.removeValue(forKey: key) }

            byCategory[catID] = byKey
            // A renamed category still has to find its old self — but only if
            // exactly one category answers to that name.
            let catNameKeys = [category["sourceName"], category["name"]]
                .compactMap { ($0 as? String).map { "name:\(matchKey($0))" } }
            for key in Set(catNameKeys) {
                if byCategory[key] != nil {
                    ambiguousCategoryKeys.insert(key)
                } else {
                    byCategory[key] = byKey
                }
            }
        }
        for key in ambiguousCategoryKeys { byCategory.removeValue(forKey: key) }

        for (cIdx, category) in cats.enumerated() {
            let catID = (category["id"] as? String) ?? ""
            let catName = (category["name"] as? String).map { "name:\(matchKey($0))" } ?? ""
            guard let byKey = byCategory[catID] ?? byCategory[catName] else { continue }
            var items = (category["items"] as? [[String: Any]]) ?? []
            for (iIdx, item) in items.enumerated() {
                let id = (item["id"] as? String).map { "id:\($0)" } ?? ""
                let name = (item["name"] as? String).map { "name:\(matchKey($0))" } ?? ""
                guard let previous = byKey[id] ?? byKey[name] else { continue }
                var updated = item
                if let note = previous["note"] { updated["note"] = note }
                // A user-chosen name wins over the generator's, and keeps the
                // anchor that let it be matched at all.
                if let source = previous["sourceName"], let chosen = previous["name"] {
                    updated["name"] = chosen
                    updated["sourceName"] = source
                }
                items[iIdx] = updated
            }
            var next = category
            next["items"] = items
            cats[cIdx] = next
        }
        root["categories"] = cats
        return (try? JSONSerialization.data(withJSONObject: root)) ?? replaced
    }

    /// Append-only merge. Operates on the raw dictionaries rather than the DTOs
    /// so unknown fields — anything the parser doesn't surface — survive the
    /// round trip, the same way `addingGoal` and `mergingPersonalGoals` do.
    ///
    /// `accepting == nil` takes every new item; otherwise only incoming items
    /// whose id is in the set.
    private static func additive(current: Data, incoming: Data,
                                 accepting: Set<String>?) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any],
              let incRoot = (try? JSONSerialization.jsonObject(with: incoming)) as? [String: Any]
        else { return current }

        var cats = (root["categories"] as? [[String: Any]]) ?? []
        let incCats = (incRoot["categories"] as? [[String: Any]]) ?? []

        for incCat in incCats {
            guard let incID = incCat["id"] as? String,
                  incID != TrackerSchemaJSON.personalGoalsID else { continue }
            let incName = (incCat["name"] as? String) ?? incID
            let incItems = (incCat["items"] as? [[String: Any]]) ?? []

            let wanted = incItems.filter { item in
                guard let id = item["id"] as? String else { return false }
                return accepting?.contains(id) ?? true
            }
            guard !wanted.isEmpty else { continue }

            // Id first. The name fallback exists because a regeneration
            // routinely re-slugs category ids, and without it every rerun
            // duplicates the whole tracker — but it only applies when exactly
            // ONE existing category carries that name. Two categories called
            // "Bosses" with different ids are two categories, and folding an
            // incoming one into whichever came first loses its identity.
            let nameMatches = cats.indices.filter {
                matchKey((cats[$0]["name"] as? String) ?? "") == matchKey(incName)
            }
            let idx = cats.firstIndex { ($0["id"] as? String) == incID }
                ?? (nameMatches.count == 1 ? nameMatches[0] : nil)

            guard let idx else {
                // Whole category is new — take it, but only carrying the items
                // that were accepted.
                var fresh = incCat
                fresh["items"] = wanted
                cats.append(fresh)
                continue
            }

            var existing = cats[idx]
            var items = (existing["items"] as? [[String: Any]]) ?? []
            // Ids grow as appends happen — a payload repeating an id must not
            // append both rows, since progress is keyed by item id and two
            // rows would share one checkmark. Names are checked only against
            // what was ALREADY in the category before this payload: that's
            // the re-import guard (a regeneration returning "False Knight"
            // under a fresh id must not double it), but names inside one
            // payload are not identities — a pasted list legitimately has
            // "Chest" at three locations under three ids, and growing the
            // name set silently swallowed all but the first.
            var haveIDs = Set(items.compactMap { $0["id"] as? String })
            let preexistingNames = Set(items.compactMap { ($0["name"] as? String).map(matchKey) })

            for item in wanted {
                let id = (item["id"] as? String) ?? ""
                let nameKey = matchKey((item["name"] as? String) ?? "")
                guard !haveIDs.contains(id), !preexistingNames.contains(nameKey) else { continue }
                haveIDs.insert(id)
                items.append(item)
            }
            existing["items"] = items
            cats[idx] = existing
        }

        root["categories"] = cats
        if root["schemaVersion"] == nil { root["schemaVersion"] = 1 }

        // A tracker with no run template yet should still gain one the incoming
        // schema brought along — that's additive, and never overwrites a
        // template the game already has (Hades' hand-built one, say).
        if TrackerSchemaJSON.runTemplate(from: current) == nil,
           let incTemplate = incRoot["runTemplate"] {
            root["runTemplate"] = incTemplate
        }

        return (try? JSONSerialization.data(withJSONObject: root)) ?? current
    }
}
