import SwiftUI
import SwiftData

/// The game page's sections, in default order — the same shape as
/// `StatsCard`: reorder by drag, hide by switch, stored device-local in
/// `@AppStorage` as a library-wide default. Which sections a page shows is a
/// reading preference (like which stats cards you care about), not library
/// data, so it deliberately doesn't sync or cost a schema field. A per-game
/// override would be a `Game` property — logged for a future schema batch,
/// not built.
///
/// Hiding is not deleting: a hidden Notes section still holds its notes, and
/// they survive export, sync, and un-hiding. And hiding is distinct from a
/// section that's absent anyway — Runs without a template and About without a
/// summary never render regardless of this preference.
enum GamePageSection: String, CaseIterable, Identifiable {
    case sessions, beaten, runs, tracker, videos, about, media, info
    case connections, tags, review, notes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sessions:    "Sessions"
        case .beaten:      "Beaten"
        case .runs:        "Runs"
        case .tracker:     "Tracker"
        case .videos:      "Guides & Videos"
        case .about:       "About"
        case .media:       "Media"
        case .info:        "Game Info"
        case .connections: "Connections"
        case .tags:        "Tags"
        case .review:      "Review"
        case .notes:       "Notes"
        }
    }

    var icon: String {
        switch self {
        case .sessions:    "stopwatch"
        case .beaten:      "flag.checkered"
        case .runs:        "arrow.2.squarepath"
        case .tracker:     "checklist"
        case .videos:      "play.rectangle"
        case .about:       "text.alignleft"
        case .media:       "photo.stack"
        case .info:        "info.circle"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .tags:        "tag"
        case .review:      "star.bubble"
        case .notes:       "note.text"
        }
    }

    /// Stored order (comma-joined raw values) → full render order. Unknown
    /// tokens are dropped; sections absent from the stored order slot back in
    /// at their default position relative to the ones around them — so a
    /// future build's new section appears for arranged users exactly as it
    /// does for fresh installs. Same algorithm as `StatsCard.resolveOrder`.
    /// **The sections that open on a game you have never touched.**
    ///
    /// Tim's minimum, plus the two whose empty state is a control: *"at minimum
    /// it should be game info and connections. It's weird right now that I
    /// can't see anything about the game itself aside from the cover and
    /// title."* About is deliberately NOT here — it is the long one, a wall of
    /// IGDB prose on every game — but it is one toggle away in Settings, which
    /// is the point of making this settable rather than deciding it for people.
    static let builtInExpanded: Set<GamePageSection> =
        [.sessions, .tracker, .info, .connections, .notes]

    /// The library-wide default, from settings or the built-in set.
    static func defaultExpanded(stored: String?) -> Set<GamePageSection> {
        guard let stored else { return builtInExpanded }
        // An empty string is a real answer — "open nothing" — and must not
        // fall through to the built-in set.
        return Set(stored.split(separator: ",").compactMap { GamePageSection(rawValue: String($0)) })
    }

    /// Whether THIS section on THIS game opens, default plus any override.
    static func isExpanded(_ section: GamePageSection,
                           defaults: Set<GamePageSection>,
                           overrides: String?) -> Bool {
        if let value = overrideMap(overrides)[section] { return value }
        return defaults.contains(section)
    }

    static func overrideMap(_ raw: String?) -> [GamePageSection: Bool] {
        var map: [GamePageSection: Bool] = [:]
        for pair in (raw ?? "").split(separator: ",") {
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let s = GamePageSection(rawValue: String(parts[0])) else { continue }
            map[s] = parts[1] == "1"
        }
        return map
    }

    /// Writing an override back. A choice that MATCHES the default is dropped
    /// rather than stored, so a game stops disagreeing once it agrees again —
    /// otherwise changing the library default would leave games pinned to the
    /// old one with nothing on screen explaining why.
    static func writingOverride(_ section: GamePageSection, open: Bool,
                                into raw: String?,
                                defaults: Set<GamePageSection>) -> String? {
        var map = overrideMap(raw)
        if open == defaults.contains(section) { map[section] = nil } else { map[section] = open }
        guard !map.isEmpty else { return nil }
        return allCases.compactMap { s in map[s].map { "\(s.rawValue):\($0 ? 1 : 0)" } }
            .joined(separator: ",")
    }

    static func resolveOrder(stored: String) -> [GamePageSection] {
        let chosen = stored.split(separator: ",").compactMap { GamePageSection(rawValue: String($0)) }
        guard !chosen.isEmpty else { return Array(allCases) }
        var result = chosen
        for (index, section) in allCases.enumerated() where !result.contains(section) {
            let predecessors = allCases.prefix(index).reversed()
            if let anchor = predecessors.first(where: { result.contains($0) }),
               let at = result.firstIndex(of: anchor) {
                result.insert(section, at: at + 1)
            } else {
                result.insert(section, at: 0)
            }
        }
        return result
    }

    static func hiddenSet(stored: String) -> Set<GamePageSection> {
        Set(stored.split(separator: ",").compactMap { GamePageSection(rawValue: String($0)) })
    }
}

/// Mirror of `StatsArrangeSheet` for the game page. Reset clears the stored
/// preferences rather than writing a copy of the defaults, so a future
/// build's new sections appear for reset users exactly as they do for fresh
/// installs.
struct GameArrangeSheet: View {
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    @AppStorage("gamePageShowStats") private var showGameStats = true

    private var expandedDefaults: Set<GamePageSection> {
        GamePageSection.defaultExpanded(stored: themeSettings.first?.expandedSectionsRaw)
    }

    private func expandedBinding(_ section: GamePageSection) -> Binding<Bool> {
        Binding(
            get: { expandedDefaults.contains(section) },
            set: { open in
                var next = expandedDefaults
                if open { next.insert(section) } else { next.remove(section) }
                let settings = ThemePalette.fetchOrCreate(in: context)
                // Ordered by `allCases` so the stored string is stable and two
                // devices that set the same sections write the same value.
                settings.expandedSectionsRaw = GamePageSection.allCases
                    .filter(next.contains).map(\.rawValue).joined(separator: ",")
                settings.updatedAt = .now
            })
    }

    /// **A section is one of three things, not two switches.**
    ///
    /// Shown-or-hidden and opens-or-not used to be separate lists, which let
    /// you say something meaningless: hidden AND open by default. Nothing
    /// stopped it and nothing surfaced it. As one control the state cannot be
    /// written down, so it cannot happen.
    ///
    /// Tim picked this over a toggle-plus-chip for a reason I had missed:
    /// *"with number 2 you can immediately tap it as open, which turns it on
    /// and open in one tap."* Reaching the most common state costs one tap
    /// rather than two.
    enum SectionState: String, CaseIterable, Identifiable {
        case off, closed, open
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off:    "Off"
            case .closed: "Closed"
            case .open:   "Open"
            }
        }
    }

    /// Reads and writes BOTH stores, which is the point of merging the lists:
    /// hiding is device-local and opening is synced, and someone arranging
    /// their page should not have to know that.
    private func stateBinding(_ section: GamePageSection) -> Binding<SectionState> {
        Binding(
            get: {
                if hidden.contains(section) { return .off }
                return expandedDefaults.contains(section) ? .open : .closed
            },
            set: { state in
                visibilityBinding(section).wrappedValue = (state != .off)
                // Off clears the open flag too. Otherwise turning a section
                // back on would silently restore an "opens" it no longer shows
                // anywhere — the invisible state coming back by the side door.
                expandedBinding(section).wrappedValue = (state == .open)
            })
    }

    private var order: [GamePageSection] { GamePageSection.resolveOrder(stored: orderRaw) }
    private var hidden: Set<GamePageSection> { GamePageSection.hiddenSet(stored: hiddenRaw) }

    var body: some View {
        NavigationStack {
            List {
                // The header isn't a reorderable section — it's always first,
                // it's the thing the page is — but it is the one part of the
                // page a non-timer wants gone, so it gets its own switch above
                // the list rather than a row that can be dragged into the
                // middle of the document.
                Section {
                    Toggle(isOn: $showGameStats) {
                        Label("Game stats", systemImage: "clock")
                    }
                    .tint(LSTheme.accent)
                } header: {
                    Text("Header")
                } footer: {
                    Text("Played, sessions, beaten, and runs, across every playthrough. Turn it off if you don't time your play.")
                }

                Section {
                    ForEach(order) { section in
                        // Three things want this row's width and only two fit.
                        // The picker holds three fixed words and can't give
                        // ground — narrowed to 152 it truncated its own
                        // selected segment to "Clos…" — and the drag handle
                        // is the system's. So the icon goes: with it there,
                        // "Sessions" wrapped to "Ses-/sions" and
                        // "Connections" truncated. The name is the thing you
                        // read down this list; the icon was decoration it
                        // could not afford. At accessibility sizes nothing
                        // fits side by side and the row stacks, same rule as
                        // the playthrough picker.
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(spacing: 10))
                        layout {
                            Text(section.displayName)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Picker("", selection: stateBinding(section)) {
                                ForEach(SectionState.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            // nil = unconstrained, which is what the stacked
                            // layout wants: full width on its own line.
                            .frame(width: typeSize.isAccessibilitySize ? nil : 178)
                        }
                    }
                    .onMove { from, to in
                        var sections = order
                        sections.move(fromOffsets: from, toOffset: to)
                        orderRaw = sections.map(\.rawValue).joined(separator: ",")
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    // Both storage rules, because they differ and the
                    // difference is deliberate — and the per-game one, because
                    // it is what makes changing the default safe.
                    Text("Off hides a section — its contents are kept, nothing is deleted. Open and Closed decide how a section arrives on a game you haven't adjusted, and that choice follows you to your other devices; so does closing a section on one particular game. Order and hiding stay on this device.")
                }
            }
            #if !os(macOS)
            // Keep the drag handles visible without an Edit button; macOS
            // has no editMode and reorders List rows natively.
            .environment(\.editMode, .constant(.active))
            #endif
            // Not "Arrange Sections", because it changes every game page
            // rather than the one you came from.
            //
            // It USED to open from a game's own menu, and this comment used to
            // say so; it lives in Settings → Personalization now, which is the
            // other half of a complaint Tim has already made — *"it's weird
            // that I have to jump out of a game page, go back to the home tab,
            // tap settings, scroll until I find game page and tracker
            // settings."* Reaching it from both places is the open question.
            .navigationTitle("All Game Pages")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Not Cancel — it applies immediately, like everything
                    // else in this sheet.
                    Button("Reset Layout") {
                        orderRaw = ""
                        hiddenRaw = ""
                        showGameStats = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .lsSheet()
    }

    private func visibilityBinding(_ section: GamePageSection) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(section) },
            set: { visible in
                var set = hidden
                if visible { set.remove(section) } else { set.insert(section) }
                // Preserve canonical order in storage so the raw string is
                // stable and diffable rather than insertion-ordered.
                hiddenRaw = GamePageSection.allCases.filter(set.contains)
                    .map(\.rawValue).joined(separator: ",")
            })
    }
}

/// Identity for the backdrop lookup task: the game AND the library-wide
/// background preference, so changing either re-resolves. A plain `game.id`
/// would leave an open page showing key art after the user switched the
/// preference to screenshots.
struct BackdropRequest: Equatable {
    let gameID: UUID
    let background: ThemePageBackground
}
