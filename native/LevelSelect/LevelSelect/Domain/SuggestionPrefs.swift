import Foundation

/// What you want suggested, and what you never want to see again.
///
/// Tim, 2026-09-17: *"I know I like to browse games from publishers sometimes
/// because I feel like companies like Capcom choose to publish games of a
/// certain quality… Maybe though, we could let users choose to favorite or
/// follow (or hide from suggestions) certain studios and publishers, that way
/// they aren't bombarded by every studio for every game they've played."*
///
/// Three lists, four kinds of thing. **Followed** is a thumb on the scale, not
/// a filter: followed things come first and the rest stay, lightly scattered,
/// because a suggestion list that only ever shows you what you already asked
/// for stops being a suggestion list. **Hidden** is absolute.
///
/// **Synced since V7 (09-18).** UserDefaults stays the working copy — every
/// read here is synchronous and hot — and `ThemeSettings.suggestionPrefsRaw`
/// carries it between devices: a change here calls `onChange` with the whole
/// snapshot, and a change arriving by sync is `apply`'d back. News → New &
/// Upcoming's chosen systems ride in the same snapshot, since they are the
/// same kind of thing: what you want to hear about.
enum SuggestionPrefs {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case studio, publisher, tag, system
        var id: String { rawValue }

        var label: String {
            switch self {
            case .studio: "Studios"
            case .publisher: "Publishers"
            case .tag: "Tags"
            case .system: "Systems"
            }
        }

        var blurb: String {
            switch self {
            case .studio: "The people who make the games."
            case .publisher: "Who puts them out. Some publishers pick well."
            case .tag: "Your own words for what you like."
            case .system: "Suggest games for these."
            }
        }
    }

    /// Follow, hide, or neither.
    enum Stance: String, Sendable {
        case followed, hidden, neutral
    }

    static func key(_ kind: Kind, _ stance: Stance) -> String {
        "levelselect.suggest.\(kind.rawValue).\(stance.rawValue)"
    }

    static func names(_ kind: Kind, _ stance: Stance) -> Set<String> {
        guard stance != .neutral else { return [] }
        return Set(UserDefaults.standard.array(forKey: key(kind, stance)) as? [String] ?? [])
    }

    static func stance(_ kind: Kind, _ name: String) -> Stance {
        let folded = fold(name)
        if names(kind, .hidden).contains(folded) { return .hidden }
        if names(kind, .followed).contains(folded) { return .followed }
        return .neutral
    }

    static func set(_ stance: Stance, _ kind: Kind, _ name: String) {
        let folded = fold(name)
        for other in [Stance.followed, .hidden] {
            var list = names(kind, other)
            if other == stance { list.insert(folded) } else { list.remove(folded) }
            UserDefaults.standard.set(Array(list), forKey: key(kind, other))
        }
        changed()
    }

    // MARK: Sync

    /// News → New & Upcoming's "Your systems", comma-separated.
    static let upcomingSystemsKey = "news.upcomingSystems"

    struct Snapshot: Codable, Equatable {
        var lists: [String: [String]] = [:]
        var upcomingSystems: String?
    }

    /// Set by the app: writes the snapshot to the synced settings row.
    @MainActor static var onChange: ((String) -> Void)?

    /// Something local changed; send it.
    static func changed() {
        let raw = encoded()
        Task { @MainActor in onChange?(raw) }
    }

    static func snapshot(_ defaults: UserDefaults = .standard) -> Snapshot {
        var s = Snapshot()
        for kind in Kind.allCases {
            for stance in [Stance.followed, .hidden] {
                let list = (defaults.array(forKey: key(kind, stance)) as? [String] ?? []).sorted()
                if !list.isEmpty { s.lists["\(kind.rawValue).\(stance.rawValue)"] = list }
            }
        }
        let systems = defaults.string(forKey: upcomingSystemsKey) ?? ""
        s.upcomingSystems = systems.isEmpty ? nil : systems
        return s
    }

    static func encoded(_ defaults: UserDefaults = .standard) -> String {
        let data = (try? JSONEncoder.sorted.encode(snapshot(defaults))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// What arrived by sync, into the working copy. The first time a device
    /// meets the synced copy it MERGES — follows and hides from both — so a
    /// phone's choices aren't wiped by the iPad's; after that, the synced copy
    /// simply wins. Returns the merged snapshot when it should be sent back.
    @discardableResult
    static func apply(_ raw: String, _ defaults: UserDefaults = .standard) -> String? {
        guard let remote = try? JSONDecoder().decode(Snapshot.self, from: Data(raw.utf8)) else { return nil }
        let firstMeeting = !defaults.bool(forKey: "levelselect.suggest.synced")
        var result = remote
        if firstMeeting {
            let local = snapshot(defaults)
            for (k, v) in local.lists { result.lists[k] = Array(Set(v).union(remote.lists[k] ?? [])).sorted() }
            // Hidden beats followed for anything both devices touched.
            for kind in Kind.allCases {
                let hidden = Set(result.lists["\(kind.rawValue).hidden"] ?? [])
                if let f = result.lists["\(kind.rawValue).followed"] {
                    result.lists["\(kind.rawValue).followed"] = f.filter { !hidden.contains($0) }
                }
            }
            if result.upcomingSystems == nil { result.upcomingSystems = local.upcomingSystems }
            defaults.set(true, forKey: "levelselect.suggest.synced")
        }
        for kind in Kind.allCases {
            for stance in [Stance.followed, .hidden] {
                defaults.set(result.lists["\(kind.rawValue).\(stance.rawValue)"] ?? [], forKey: key(kind, stance))
            }
        }
        defaults.set(result.upcomingSystems ?? "", forKey: upcomingSystemsKey)
        guard firstMeeting, result != remote else { return nil }
        return encoded(defaults)
    }

    /// Case and spacing aside, so "capcom" and "Capcom" are one company.
    static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: Applying them

    /// Whether a suggestion is one you've said no to.
    ///
    /// A system is hidden only when EVERY system it's on is hidden: a game on
    /// the Switch and the Xbox 360 is still a Switch game.
    static func isHidden(developers: [String], publishers: [String],
                         tags: [String], platforms: [String]) -> Bool {
        let hiddenStudios = names(.studio, .hidden)
        if developers.contains(where: { hiddenStudios.contains(fold($0)) }) { return true }
        let hiddenPublishers = names(.publisher, .hidden)
        if publishers.contains(where: { hiddenPublishers.contains(fold($0)) }) { return true }
        let hiddenTags = names(.tag, .hidden)
        if tags.contains(where: { hiddenTags.contains(fold($0)) }) { return true }
        let hiddenSystems = names(.system, .hidden)
        if !hiddenSystems.isEmpty, !platforms.isEmpty,
           platforms.allSatisfy({ hiddenSystems.contains(fold(PlatformKey.canonical($0))) }) {
            return true
        }
        return false
    }

    static func isFollowed(developers: [String], publishers: [String],
                           tags: [String], platforms: [String]) -> Bool {
        let studios = names(.studio, .followed)
        if developers.contains(where: { studios.contains(fold($0)) }) { return true }
        let pubs = names(.publisher, .followed)
        if publishers.contains(where: { pubs.contains(fold($0)) }) { return true }
        let terms = names(.tag, .followed)
        if tags.contains(where: { terms.contains(fold($0)) }) { return true }
        let systems = names(.system, .followed)
        return platforms.contains { systems.contains(fold(PlatformKey.canonical($0))) }
    }

    /// Anything followed at all — nothing to weigh when nothing is followed.
    static var hasFollows: Bool {
        Kind.allCases.contains { !names($0, .followed).isEmpty }
    }

    /// Followed first, the rest lightly scattered — one unfollowed game after
    /// every three followed ones, so the shelf stays a suggestion list rather
    /// than a list of things you already told it you like.
    static func weave<T>(followed: [T], others: [T], everyNth: Int = 3) -> [T] {
        guard !followed.isEmpty else { return others }
        guard !others.isEmpty else { return followed }
        var out: [T] = []
        var rest = others.makeIterator()
        for (index, item) in followed.enumerated() {
            out.append(item)
            if (index + 1) % everyNth == 0, let next = rest.next() { out.append(next) }
        }
        while let next = rest.next() { out.append(next) }
        return out
    }
}

extension JSONEncoder {
    /// Stable output, so an unchanged snapshot is an unchanged string and
    /// doesn't cost a CloudKit write.
    static var sorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
