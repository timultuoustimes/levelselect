import SwiftUI

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

    private var order: [GamePageSection] { GamePageSection.resolveOrder(stored: orderRaw) }
    private var hidden: Set<GamePageSection> { GamePageSection.hiddenSet(stored: hiddenRaw) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { section in
                        Toggle(isOn: visibilityBinding(section)) {
                            Label(section.displayName, systemImage: section.icon)
                        }
                        .tint(LSTheme.accent)
                    }
                    .onMove { from, to in
                        var sections = order
                        sections.move(fromOffsets: from, toOffset: to)
                        orderRaw = sections.map(\.rawValue).joined(separator: ",")
                    }
                } footer: {
                    Text("Applies to every game page. Hidden sections keep their contents — nothing is deleted.")
                }
            }
            #if !os(macOS)
            // Keep the drag handles visible without an Edit button; macOS
            // has no editMode and reorders List rows natively.
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Arrange Sections")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        orderRaw = ""
                        hiddenRaw = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
