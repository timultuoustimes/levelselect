import Foundation

/// A collection that fills itself.
///
/// Tim, 2026-09-05, asked whether a saved filter is a Smart Collection: yes.
/// It inherits the Collections tab, the prompts, the naming and the composite
/// art, and it costs one field — `GameCollection.filterRuleRaw` — instead of
/// a model. The rule is exactly what Library's filter can express today, so
/// "Save these filters as a collection" is the whole front door.
///
/// Stored as `status=playing;system=Super Nintendo;ownership=physical;tag=x`,
/// every part optional. An empty rule is not a smart collection.
struct SmartCollectionRule: Equatable, Hashable {
    var status: GameStatus?
    /// The displayed short name, the way Library's filter matches it.
    var system: String?
    var ownership: OwnershipFilter?
    var tag: String?

    var isEmpty: Bool { status == nil && system == nil && ownership == nil && tag == nil }

    static func parse(_ raw: String?) -> SmartCollectionRule? {
        guard let raw, !raw.isEmpty else { return nil }
        var rule = SmartCollectionRule()
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "status":    rule.status = GameStatus(rawValue: kv[1])
            case "system":    rule.system = kv[1].isEmpty ? nil : kv[1]
            case "tag":       rule.tag = kv[1].isEmpty ? nil : kv[1]
            case "ownership":
                rule.ownership = kv[1] == "unset" ? .unset : Ownership(rawValue: kv[1]).map { .kind($0) }
            default: break
            }
        }
        return rule.isEmpty ? nil : rule
    }

    var raw: String {
        var parts: [String] = []
        if let status { parts.append("status=\(status.rawValue)") }
        if let system { parts.append("system=\(system)") }
        if let ownership {
            switch ownership {
            case .kind(let k): parts.append("ownership=\(k.rawValue)")
            case .unset:       parts.append("ownership=unset")
            }
        }
        if let tag { parts.append("tag=\(tag)") }
        return parts.joined(separator: ";")
    }

    /// Library's own predicate, minus search and the bundle hiding — a rule
    /// is about what a game IS, not about what you typed just now.
    func matches(_ game: Game) -> Bool {
        game.status != .wishlist
        && game.deletedAt == nil
        && (status == nil || game.status == status)
        && (tag == nil || game.userTags.contains(tag!))
        && (system == nil || PlatformShort.ownedMatches(game.ownedPlatformNames, short: system!))
        && (ownership?.matches(game) ?? true)
    }

    func members(in games: [Game]) -> [Game] {
        games.filter(matches)
    }

    /// The words the rule is made of, for a chip row.
    func describe(statusName: (GameStatus) -> String) -> [String] {
        var parts: [String] = []
        if let status { parts.append(statusName(status)) }
        if let system { parts.append(system) }
        if let ownership {
            switch ownership {
            case .kind(let k): parts.append(k.label)
            case .unset:       parts.append("No ownership set")
            }
        }
        if let tag { parts.append("#\(tag)") }
        return parts
    }
}

extension GameCollection {
    var smartRule: SmartCollectionRule? { SmartCollectionRule.parse(filterRuleRaw) }
    var isSmart: Bool { smartRule != nil }

    /// The games in this collection — the rule's answer for a smart one, the
    /// hand-picked list otherwise.
    func members(in games: [Game]) -> [Game] {
        if let rule = smartRule { return rule.members(in: games) }
        let ids = Set(gameIDs)
        return games.filter { ids.contains($0.id.uuidString) }
    }
}

// App target only: `Repository` is shared with the widgets, and
// `OwnershipFilter` is not, so the write that takes a rule lives beside it.
extension Repository {
    /// A collection with a rule instead of a list.
    @discardableResult
    func createSmartCollection(name: String, rule: SmartCollectionRule) -> GameCollection {
        let collection = createCollection(name: name.trimmingCharacters(in: .whitespaces))
        collection.filterRuleRaw = rule.raw
        collection.updatedAt = .now
        collection.revision += 1
        persist()
        return collection
    }
}
