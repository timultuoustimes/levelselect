import Foundation

/// What Home is made of, in order — and whose choice that is.
///
/// **Home is a self-portrait, and the person decides what is in it.** On
/// 2026-08-29 the systems shelf moved to Library because it read as an index
/// — another route to the same games. Tim, 2026-09-05: *"someone's consoles
/// and collections are more about them than they are about their library of
/// games. Like if someone's a Nintendo person, it's going to most likely show
/// a bunch of Nintendo consoles across their home."* Both readings are true of
/// the same pixels, which is exactly why the app stops deciding. Library keeps
/// everything; a block on Home is an extra place to see it, never a move.
///
/// Stored in `ThemeSettings.homeLayoutRaw`, **synced** — deliberately the
/// opposite of the game page's device-local section order. A self-portrait
/// follows you; which sections you closed on the iPad does not.
///
/// Grammar, comma-separated, one token per block, `-` prefix for hidden:
///
///     continue,systems:6:grid,status:playing,collection:<uuid>,-collections
///
/// Unknown tokens are dropped; blocks a future build adds slot back in at
/// their default position, the same rule `GamePageSection.resolveOrder` uses.
enum HomeBlock: Hashable, Identifiable {
    case continuePlaying
    case systems
    case status(GameStatus)
    /// Every collection, as a shelf of composite tiles — Library's shelf.
    case collections
    /// One collection as its own shelf, its covers in a row under its name.
    /// "Six That Made Me" on your Home says more than a tile does.
    case collection(UUID)

    var id: String { token }

    /// The stored form, without the systems block's count and style — those
    /// live on the layout, because there is only ever one systems block.
    var token: String {
        switch self {
        case .continuePlaying:      "continue"
        case .systems:              "systems"
        case .status(let status):   "status:\(status.rawValue)"
        case .collections:          "collections"
        case .collection(let id):   "collection:\(id.uuidString.lowercased())"
        }
    }

    /// `systems:6:grid` parses as `.systems`; the trailing fields are read by
    /// `HomeLayout` separately so an older build that knows fewer fields still
    /// keeps the block.
    static func parse(_ token: Substring) -> HomeBlock? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.first.map(String.init) {
        case "continue":    return .continuePlaying
        case "systems":     return .systems
        case "collections": return .collections
        case "status":
            guard parts.count >= 2, let s = GameStatus(rawValue: String(parts[1])),
                  s != .wishlist else { return nil }
            return .status(s)
        case "collection":
            guard parts.count >= 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
            return .collection(id)
        default:
            return nil
        }
    }
}

/// How the systems block draws.
///
/// Tim, 2026-09-08: *"default to 3x2, but let them switch to a scrolling row
/// on iPhone if they prefer that, or have an odd number of systems. Someone
/// might be coming into it with 4, and the scroll is just visually better."*
enum SystemsBlockStyle: String, CaseIterable, Identifiable {
    /// The display case: a 3-wide grid, everything visible, no scroll.
    case grid
    /// Library's shelf: one horizontal row that scrolls.
    case row
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: "Case"
        case .row:  "Row"
        }
    }
    var systemImage: String {
        switch self {
        case .grid: "square.grid.3x2"
        case .row:  "rectangle.split.3x1"
        }
    }
}

struct HomeLayout: Equatable {
    struct Entry: Hashable, Identifiable {
        var block: HomeBlock
        var hidden: Bool = false
        var id: String { block.id }
    }

    var entries: [Entry]
    /// How many systems reach Home; the rest sit behind "See all".
    var systemsCount: Int = HomeLayout.defaultSystemsCount
    var systemsStyle: SystemsBlockStyle = .grid

    static let defaultSystemsCount = 6
    /// A count of zero would be a hidden block wearing a number; the toggle
    /// is how a block hides.
    static let systemsCountRange = 1...12

    /// **The default composition — the one most people will ever see.**
    ///
    /// Continue Playing, then the display case, then the shelves in Home's
    /// order. Everything else exists as a hidden entry so Arrange Home can
    /// offer it with a switch rather than a separate "add" menu: the shelves
    /// Library keeps (Backlog, Finished, the rest) and the all-collections
    /// tile shelf. Pinned collections are added by name.
    static var defaultEntries: [Entry] {
        var list: [Entry] = [Entry(block: .continuePlaying), Entry(block: .systems)]
        list += GameStatus.homeOrder.map { Entry(block: .status($0)) }
        list.append(Entry(block: .collections, hidden: true))
        for status in GameStatus.allCases
        where status != .wishlist && !GameStatus.homeOrder.contains(status) {
            list.append(Entry(block: .status(status), hidden: true))
        }
        return list
    }

    static var standard: HomeLayout { HomeLayout(entries: defaultEntries) }

    /// Stored string → layout, with two kinds of forgiveness.
    ///
    /// `legacyHiddenStatuses` is the device-local "Hide from Home" set that
    /// predates this: honored only while nothing is stored, so a shelf hidden
    /// last month stays hidden until the person arranges Home, at which point
    /// the synced layout takes over and the old set is spent.
    static func resolve(raw: String?, legacyHiddenStatuses: Set<GameStatus> = []) -> HomeLayout {
        guard let raw, !raw.isEmpty else {
            var layout = standard
            for i in layout.entries.indices {
                if case .status(let s) = layout.entries[i].block, legacyHiddenStatuses.contains(s) {
                    layout.entries[i].hidden = true
                }
            }
            return layout
        }

        var layout = HomeLayout(entries: [])
        var seen = Set<String>()
        for piece in raw.split(separator: ",") {
            var token = piece.trimmingCharacters(in: .whitespaces)[...]
            let hidden = token.hasPrefix("-")
            if hidden { token = token.dropFirst() }
            guard let block = HomeBlock.parse(token), !seen.contains(block.id) else { continue }
            seen.insert(block.id)
            if block == .systems {
                let parts = token.split(separator: ":")
                if parts.count >= 2, let n = Int(parts[1]), systemsCountRange.contains(n) {
                    layout.systemsCount = n
                }
                if parts.count >= 3, let style = SystemsBlockStyle(rawValue: String(parts[2])) {
                    layout.systemsStyle = style
                }
            }
            layout.entries.append(Entry(block: block, hidden: hidden))
        }

        // Anything the default has that the stored order lacks slots back in
        // beside its default neighbour, keeping the default's hidden flag —
        // so a status added by a later build appears for arranged users the
        // way it does for fresh installs.
        let defaults = defaultEntries
        for (index, entry) in defaults.enumerated() where !seen.contains(entry.id) {
            let predecessors = defaults.prefix(index).reversed()
            if let anchor = predecessors.first(where: { seen.contains($0.id) }),
               let at = layout.entries.firstIndex(where: { $0.id == anchor.id }) {
                layout.entries.insert(entry, at: at + 1)
            } else {
                layout.entries.insert(entry, at: 0)
            }
            seen.insert(entry.id)
        }
        return layout
    }

    /// Layout → stored string. The systems token carries its count and style.
    var raw: String {
        entries.map { entry in
            var token = entry.block.token
            if entry.block == .systems { token += ":\(systemsCount):\(systemsStyle.rawValue)" }
            return entry.hidden ? "-" + token : token
        }
        .joined(separator: ",")
    }

    var visibleBlocks: [HomeBlock] { entries.filter { !$0.hidden }.map(\.block) }

    func isHidden(_ block: HomeBlock) -> Bool {
        entries.first { $0.block == block }?.hidden ?? true
    }

    mutating func setHidden(_ block: HomeBlock, _ hidden: Bool) {
        if let i = entries.firstIndex(where: { $0.block == block }) {
            entries[i].hidden = hidden
        } else {
            entries.append(Entry(block: block, hidden: hidden))
        }
    }

    mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        entries.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// A collection joins Home visible, at the end — where a new shelf is
    /// noticed — and the person drags it from there.
    mutating func pin(collection id: UUID) {
        if let i = entries.firstIndex(where: { $0.block == .collection(id) }) {
            entries[i].hidden = false
        } else {
            entries.append(Entry(block: .collection(id)))
        }
    }

    mutating func unpin(collection id: UUID) {
        entries.removeAll { $0.block == .collection(id) }
    }

    var pinnedCollections: [UUID] {
        entries.compactMap { if case .collection(let id) = $0.block { id } else { nil } }
    }
}

// MARK: - Systems: which, and in what order

/// How the systems block is sorted — and "custom" is what drag produces.
///
/// Tim asked for three orders: personal favorite (drag), console release
/// order, and by how many games you have. Release order is North American
/// initial release, from `PlatformEra`, authored for this. "Order I acquired
/// them" is deliberately absent: it needs the console record (build 39) and
/// arrives as a fourth sort with it.
enum SystemsSort: String, CaseIterable, Identifiable {
    case custom, release, mostGames, alphabetical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .custom:       "Custom"
        case .release:      "Release order (North America)"
        case .mostGames:    "Most games"
        case .alphabetical: "A–Z"
        }
    }
    var systemImage: String {
        switch self {
        case .custom:       "hand.draw"
        case .release:      "calendar"
        case .mostGames:    "number"
        case .alphabetical: "textformat.abc"
        }
    }
}

/// Which consoles Home shows, in your order — `ThemeSettings.homeSystemsRaw`.
///
/// Stored as `sort=release,Super Nintendo Entertainment System,Sega Genesis,…`:
/// the sort token says how the list was last produced, and the list itself
/// is the order. Choosing a sort rewrites the list; dragging afterwards makes
/// it custom. Systems in the library but not in the list — a console you
/// just added a game for — append at the end, so they land in "See all"
/// rather than vanishing.
enum HomeSystems {
    typealias Group = (platform: String, count: Int)

    static func parse(_ raw: String?) -> (sort: SystemsSort, order: [String]) {
        var sort = SystemsSort.custom
        var order: [String] = []
        for piece in (raw ?? "").split(separator: ",") {
            let token = piece.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("sort=") {
                sort = SystemsSort(rawValue: String(token.dropFirst("sort=".count))) ?? .custom
            } else if !token.isEmpty, !order.contains(token) {
                order.append(token)
            }
        }
        return (sort, order)
    }

    static func raw(order: [String], sort: SystemsSort) -> String {
        (["sort=\(sort.rawValue)"] + order).joined(separator: ",")
    }

    /// Every system in the library, in the stored order, newcomers last.
    static func ordered(raw: String?, available: [Group]) -> [Group] {
        let stored = parse(raw)
        var byName: [String: Group] = [:]
        for g in available { byName[g.platform] = g }
        var result: [Group] = []
        for name in stored.order {
            if let g = byName.removeValue(forKey: name) { result.append(g) }
        }
        // Newcomers in the app's own order, so two devices agree on where a
        // new console lands.
        result += sorted(Array(byName.values), by: .mostGames)
        return result
    }

    static func sorted(_ groups: [Group], by sort: SystemsSort) -> [Group] {
        switch sort {
        case .custom:
            return groups
        case .release:
            // Unknown years — "Other", a storefront — sink to the end, A–Z.
            return groups.sorted {
                let a = PlatformEra.releaseYear($0.platform) ?? Int.max
                let b = PlatformEra.releaseYear($1.platform) ?? Int.max
                return a == b ? PlatformShort.name($0.platform) < PlatformShort.name($1.platform) : a < b
            }
        case .mostGames:
            return groups.sorted {
                $0.count == $1.count
                    ? PlatformShort.name($0.platform) < PlatformShort.name($1.platform)
                    : $0.count > $1.count
            }
        case .alphabetical:
            return groups.sorted { PlatformShort.name($0.platform) < PlatformShort.name($1.platform) }
        }
    }
}
