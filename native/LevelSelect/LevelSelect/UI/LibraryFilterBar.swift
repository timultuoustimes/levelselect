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
struct LibraryFilterBar: View {
    @Binding var statusFilter: GameStatus?
    @Binding var platformFilter: String?
    @Binding var ownershipFilter: String?
    @Binding var tagFilter: String?

    /// Counted with every OTHER filter applied but this axis ignored, so a
    /// count answers "what would I get if I tapped this" rather than "what is
    /// on screen" — which for the active chip would always be its own total,
    /// and for the rest would be zero.
    let ownershipCounts: [Ownership: Int]
    let tags: [String]

    private var ownerships: [Ownership] {
        Ownership.allCases.filter { (ownershipCounts[$0] ?? 0) > 0 }
    }

    /// Nothing to show on an empty library, and nothing to show on one where
    /// no ownership has ever been recorded and no tag ever made.
    var isEmpty: Bool {
        ownerships.isEmpty && tags.isEmpty
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
                if statusFilter != nil || platformFilter != nil, !ownerships.isEmpty || !tags.isEmpty {
                    divider
                }

                ForEach(ownerships, id: \.self) { kind in
                    let active = ownershipFilter == kind.rawValue
                    FilterChip(label: kind.label, systemImage: kind.systemImage,
                               count: ownershipCounts[kind], isOn: active,
                               action: { ownershipFilter = active ? nil : kind.rawValue })
                }

                if !ownerships.isEmpty, !tags.isEmpty { divider }

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
    /// Non-nil only on chips set elsewhere (the toolbar menu), which need to
    /// say how to undo themselves. Toggles read as on/off without it.
    let onRemove: (() -> Void)?
    let action: () -> Void

    init(label: String, systemImage: String? = nil, count: Int? = nil,
         isOn: Bool, tint: Color? = nil,
         onRemove: (() -> Void)? = nil, action: @escaping () -> Void = {}) {
        self.label = label; self.systemImage = systemImage; self.count = count
        self.isOn = isOn; self.tint = tint
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
                isOn ? color : .white.opacity(0.12), lineWidth: 1))
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
    static func counts(_ games: [Game]) -> [Ownership: Int] {
        var counts: [Ownership: Int] = [:]
        for game in games {
            for kind in Ownership.allCases where game.ownership.contains(kind.rawValue) {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }
}
