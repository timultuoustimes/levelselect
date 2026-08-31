import SwiftUI

/// One row carrying every way into the shelf, showing which are on.
///
/// Library holds three axes — status, system and ownership — and the design
/// rule from 08-31 is not to rank them: they are three ways of saying how you
/// relate to a game, and none is trivia. Before this, all three were pickers
/// inside one toolbar menu, which ranked them by accident: systems ALSO had a
/// shelf with console artwork, so ownership was the one axis the page could
/// filter by but gave you no way to browse.
///
/// It also makes a combination legible. "Genesis, the ones I emulate" is the
/// case Tim named as mattering, and it used to render as four games and a
/// filled toolbar glyph with nothing on screen saying why — the same four
/// games you would get from a search that found nothing much.
/// What the ownership chips filter by.
///
/// `.unset` is the gap itself — games with no ownership recorded — and it is a
/// case rather than a sentinel string because it is a real thing you browse,
/// not an absence of a filter. Seen on Tim's own library 08-31: 143 of 160
/// games had nothing set, so the gap was larger than every kind combined.
enum OwnershipFilter: Hashable, Sendable {
    case kind(Ownership)
    case unset

    func matches(_ game: Game) -> Bool {
        switch self {
        case .kind(let kind): game.ownership.contains(kind.rawValue)
        case .unset: game.ownership.isEmpty
        }
    }
}

struct LibraryFilterBar: View {
    @Binding var statusFilter: GameStatus?
    @Binding var platformFilter: String?
    @Binding var ownershipFilter: OwnershipFilter?
    @Binding var tagFilter: String?

    /// Counted with every OTHER filter applied but this axis ignored, so a
    /// count answers "what would I get if I tapped this" rather than "what is
    /// on screen" — which for the active chip would always be its own total,
    /// and for the rest would be zero.
    let ownershipCounts: OwnershipFacet.Counts
    let tags: [String]

    private var ownerships: [Ownership] {
        Ownership.allCases.filter { (ownershipCounts.byKind[$0] ?? 0) > 0 }
    }

    /// Shown only when there is a gap to show. A library with ownership on
    /// everything should not carry a chip reading zero.
    private var showsGap: Bool { ownershipCounts.unset > 0 }

    /// Nothing to show on an empty library, and nothing to show on one where
    /// no ownership has ever been recorded and no tag ever made.
    var isEmpty: Bool {
        ownerships.isEmpty && tags.isEmpty && !showsGap
            && statusFilter == nil && platformFilter == nil
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Set from the toolbar menu, so these appear only once chosen
                // and carry their own way back out. Everything else in the row
                // is toggled in place and needs no ✕.
                if let status = statusFilter {
                    FilterChip(label: status.sectionTitle, systemImage: status.systemImage,
                               isOn: true, tint: status.color,
                               onRemove: { statusFilter = nil })
                        .accessibilityLabel("Status: \(status.sectionTitle). Remove")
                }
                if let platform = platformFilter {
                    FilterChip(label: platform, systemImage: "gamecontroller",
                               isOn: true, onRemove: { platformFilter = nil })
                        .accessibilityLabel("System: \(platform). Remove")
                }
                if statusFilter != nil || platformFilter != nil,
                   !ownerships.isEmpty || !tags.isEmpty || showsGap {
                    divider
                }

                ForEach(ownerships, id: \.self) { kind in
                    let active = ownershipFilter == .kind(kind)
                    FilterChip(label: kind.label, systemImage: kind.systemImage,
                               count: ownershipCounts.byKind[kind], isOn: active,
                               action: { ownershipFilter = active ? nil : .kind(kind) })
                }

                // Last, and dashed, so it reads as the gap rather than a fifth
                // kind of ownership. Tapping it filters to exactly the games
                // that need fixing — and the cover's own context menu carries
                // the Ownership toggles, so they can be fixed from that grid
                // without opening a single game.
                if showsGap {
                    let active = ownershipFilter == .unset
                    FilterChip(label: "No ownership set", systemImage: "questionmark.circle.dashed",
                               count: ownershipCounts.unset, isOn: active, isGap: true,
                               action: { ownershipFilter = active ? nil : .unset })
                }

                if !ownerships.isEmpty || showsGap, !tags.isEmpty { divider }

                ForEach(tags, id: \.self) { tag in
                    let active = tagFilter == tag
                    FilterChip(label: "#\(tag)", isOn: active,
                               action: { tagFilter = active ? nil : tag })
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

/// The library's chip. One shape for all four axes, because they are peers.
struct FilterChip: View {
    let label: String
    let systemImage: String?
    let count: Int?
    let isOn: Bool
    /// A status chip wears its status color; everything else wears the accent.
    let tint: Color?
    /// Drawn dashed. Reserved for "No ownership set", which is an absence
    /// rather than a value, and should not look like the chips beside it.
    let isGap: Bool
    /// Non-nil only on chips set elsewhere (the toolbar menu), which need to
    /// say how to undo themselves. Toggles read as on/off without it.
    let onRemove: (() -> Void)?
    let action: () -> Void

    init(label: String, systemImage: String? = nil, count: Int? = nil,
         isOn: Bool, tint: Color? = nil, isGap: Bool = false,
         onRemove: (() -> Void)? = nil, action: @escaping () -> Void = {}) {
        self.label = label; self.systemImage = systemImage; self.count = count
        self.isOn = isOn; self.tint = tint; self.isGap = isGap
        self.onRemove = onRemove; self.action = action
    }

    private var color: Color { tint ?? LSTheme.accent }

    var body: some View {
        Button {
            if let onRemove { onRemove() } else { action() }
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption2)
                }
                Text(label)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .monospacedDigit()
                }
                if onRemove != nil {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isOn ? color.opacity(0.45) : .white.opacity(0.07), in: .capsule)
            .overlay(Capsule().strokeBorder(
                isOn ? color : .white.opacity(0.12),
                style: StrokeStyle(lineWidth: 1, dash: isGap ? [3, 3] : [])))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}


/// Facet counting for the ownership chips.
enum OwnershipFacet {
    /// Overlapping by design — a game can be owned physically AND emulated,
    /// which is the case that made ownership worth browsing rather than
    /// picking one of four. So these do not sum to the library size, and
    /// should not: each count answers "how many of mine are like this",
    /// not "how many are in this bucket".
    ///
    /// Callers pass the library with every OTHER filter already applied and
    /// the ownership filter ignored, so a count says what you would get by
    /// tapping the chip rather than what is already on screen.
    struct Counts: Equatable {
        var byKind: [Ownership: Int] = [:]
        /// Games with nothing recorded at all — the gap chip's number.
        var unset: Int = 0
    }

    static func counts(_ games: [Game]) -> Counts {
        var counts = Counts()
        for game in games {
            if game.ownership.isEmpty {
                counts.unset += 1
                continue
            }
            for kind in Ownership.allCases where game.ownership.contains(kind.rawValue) {
                counts.byKind[kind, default: 0] += 1
            }
        }
        return counts
    }
}
