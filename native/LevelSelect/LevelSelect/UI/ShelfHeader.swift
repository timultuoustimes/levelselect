import SwiftUI

/// One way to title a group of games.
///
/// **There were five.** The build 37 UX assessment counted them: Home had a
/// chevron, the status's own glyph in its own color, a count and a "See all";
/// Library had a generic layered-stack glyph tinted accent, no chevron and no
/// way in; Wishlist had the same stack glyph in green; the Journal had bare
/// date words with a naked number on the right; the game page put its chevron
/// on the other side. Same job — *here is a group, this is what it is, here is
/// how many* — said five ways, which is most of why Library, Wishlist and
/// Journal read as three separate well-built apps rather than three parts of
/// one.
///
/// Home's was the right one, because it is the only one that says what the
/// block is *for* — the thing's own glyph, in its own color — and offers a way
/// in. This is that header, extracted so it can be the only one.
///
/// The game page's `CollapsibleSection` keeps its own right-hand chevron on
/// purpose: it collapses rather than navigates, and a different action deserves
/// a different affordance.
struct ShelfHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let title: String
    /// Nil hides the count entirely, for a shelf where it says nothing.
    var count: Int?
    /// **The glyph that means this block**, not a generic stack. A console tile
    /// for systems, the bag for the wishlist, the status's own symbol on Home.
    let systemImage: String
    /// The glyph's color. Carrying the block's own color is what makes the
    /// row say something rather than decorate.
    var tint: Color = .secondary
    /// Nil when the shelf does not collapse.
    var collapsed: Bool?
    var onToggleCollapse: () -> Void = {}
    /// Nil when there is nowhere to go. A "See all" that opens nothing is worse
    /// than none — which is why Library's shelves do not get one yet.
    var onSeeAll: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        chevron
                        glyph
                        // Title and count as ONE string here. Kept apart they
                        // became two stacked lines, because at this size each
                        // is wide enough to claim a row of its own — "Now
                        // Playing", "(2)", "See all", three lines for one thing.
                        Text(count.map { "\(title) (\($0))" } ?? title)
                            .font(.title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !(collapsed ?? false) { accessory }
                }
            } else {
                HStack(spacing: 6) {
                    chevron
                    glyph
                    Text(title).font(.title3.bold())
                    if let count {
                        Text("(\(count))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !(collapsed ?? false) { accessory }
                }
            }
        }
        .padding(.horizontal)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var chevron: some View {
        if let collapsed {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { onToggleCollapse() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            .buttonStyle(.plain)
            .lsTapTargetInline()
            // A rotated chevron is a picture of state, and VoiceOver read the
            // symbol's own name: "Forward".
            .accessibilityLabel(collapsed ? "Expand \(title)" : "Collapse \(title)")
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        }
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .foregroundStyle(tint)
            // The words carry it; this was announced ahead of them.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var accessory: some View {
        if let onSeeAll {
            Button("See all") { onSeeAll() }
                .font(.subheadline)
                .foregroundStyle(LSTheme.accent)
                .buttonStyle(.plain)
        }
        trailing
    }
}

extension ShelfHeader where Trailing == EmptyView {
    init(title: String,
         count: Int? = nil,
         systemImage: String,
         tint: Color = .secondary,
         collapsed: Bool? = nil,
         onToggleCollapse: @escaping () -> Void = {},
         onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.systemImage = systemImage
        self.tint = tint
        self.collapsed = collapsed
        self.onToggleCollapse = onToggleCollapse
        self.onSeeAll = onSeeAll
        self.trailing = EmptyView()
    }
}
