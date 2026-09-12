import SwiftUI

/// Multi-select chips for how a game is owned: Physical / Digital / Emulated.
/// Tap to toggle; a game can be more than one (double-dipped a physical +
/// digital copy). Springs + haptics to match the app's motion.
struct OwnershipControl: View {
    /// Bound to `Game.ownership` (array of raw `Ownership` values).
    @Binding var ownership: [String]
    /// Centered on the game page, where the header above it is centered too.
    /// Left-aligned everywhere else — in the Add Game form these are one field
    /// among many, and a centered row of chips in a column of left-aligned
    /// labels reads as a mistake.
    var centered = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            // Outside `ViewThatFits`, deliberately. Inside, a
            // `maxWidth: .infinity` frame would make every candidate row
            // "fit" and the measurement below would always pick the first.
            .frame(maxWidth: .infinity,
                   alignment: centered ? .center : .leading)
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            // Wrapping is right here and shrinking is not: someone who asked
            // for larger text should get larger text, on a second row.
            FlowLayout(spacing: 6) { chips(font: .caption, hPad: 8) }
        } else {
            // `ViewThatFits` measures instead of guessing. Four labeled chips
            // fit one line on a 430pt Max and don't on a 393pt phone, so this
            // row broke on some hardware and not others — and the previous fix
            // (a minimum scale factor) couldn't help, because the layout
            // decides whether to WRAP before any text is scaled. Each rung is
            // tried in order and the first that genuinely fits wins, so the
            // comfortable size still gets used wherever there's room and no
            // screen width is hardcoded anywhere.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(font: .caption,  hPad: 8) }
                HStack(spacing: 5) { chips(font: .caption2, hPad: 7) }
                HStack(spacing: 4) { chips(font: .caption2, hPad: 5) }
                balanced(font: .caption, hPad: 8)
                FlowLayout(spacing: 6) { chips(font: .caption, hPad: 8) }
            }
        }
    }

    /// **Two rows of nearly equal width, rather than a full row and a stub.**
    ///
    /// `FlowLayout` fills each line until the next chip will not fit, which is
    /// right for a paragraph and wrong for six known items: the four widest
    /// run about 360pt on a 393pt screen and the remaining two about 160, so
    /// six chips break 4 + 2 and the second row reads as leftovers. Centering
    /// that does not help — it moves the orphan to the middle. Splitting the
    /// same chips down the middle gives rows within about 8% of each other.
    ///
    /// It stays inside `ViewThatFits`, so if three chips genuinely do not fit
    /// a line — a narrow screen, a long localized label — this candidate is
    /// measured, rejected, and `FlowLayout` still catches it.
    @ViewBuilder
    private func balanced(font: Font, hPad: CGFloat) -> some View {
        let kinds = visibleKinds
        let split = (kinds.count + 1) / 2
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(kinds.prefix(split), id: \.self) { chip($0, font: font, hPad: hPad) }
            }
            HStack(spacing: 6) {
                ForEach(kinds.dropFirst(split), id: \.self) { chip($0, font: font, hPad: hPad) }
            }
        }
    }

    /// The chips this library uses, plus any this game already carries.
    ///
    /// The second half is the contract: hiding a chip is a vocabulary choice,
    /// not an edit. A game marked Rented before Rented was turned off still
    /// shows it — otherwise turning a chip off would silently strip a fact
    /// from every game that had it, and turning it back on would look like the
    /// app had remembered something it never lost.
    private var visibleKinds: [Ownership] {
        let chosen = ThemePalette.ownershipChips
        return Ownership.allCases.filter {
            chosen.contains($0) || ownership.contains($0.rawValue)
        }
    }

    @ViewBuilder
    private func chips(font: Font, hPad: CGFloat) -> some View {
        ForEach(visibleKinds, id: \.self) { kind in
            chip(kind, font: font, hPad: hPad)
        }
    }

    private func chip(_ kind: Ownership, font: Font, hPad: CGFloat) -> some View {
        let on = ownership.contains(kind.rawValue)
        return Button {
            toggle(kind)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .symbolVariant(on ? .fill : .none)
                Text(kind.label)
            }
            // No `minimumScaleFactor`: it would let a candidate row claim it
            // fits by silently shrinking its own text, which is exactly the
            // measurement `ViewThatFits` exists to make honestly.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(font.weight(.medium))
            .padding(.horizontal, hPad)
            .padding(.vertical, 5)
            // **A theme surface, not a hardcoded white.**
            //
            // The off state was `.white.opacity(0.06)`, which reads as a faint
            // capsule on the near-black ground and is invisible on a light one
            // — so in light mode the row was one chip and five loose labels,
            // which is most of why its wrap looked ragged. Same bypass as the
            // fixed blue in the platform editor, and the same fix: ask the
            // theme. Tim keeps the unselected chips visible on purpose —
            // *"it visually adds a bit of interest under the game name"* —
            // and this is what makes that true in both appearances.
            .background(on ? AnyShapeStyle(LSTheme.accent.opacity(0.20))
                           : AnyShapeStyle(LSTheme.cardFill),
                        in: .capsule)
            .overlay {
                Capsule().strokeBorder(
                    on ? LSTheme.accent.opacity(0.55) : LSTheme.hairline, lineWidth: 1)
            }
            .foregroundStyle(on ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
            // A size difference between on and off is decoration, and it is the
            // kind Reduce Motion turns off everywhere else in the app. These
            // chips were written after that sweep and missed it.
            .scaleEffect(reduceMotion ? 1 : (on ? 1 : 0.98))
        }
        .buttonStyle(.plain)
        // Caption text and 5pt of padding is about 28pt — the hit area grows,
        // the layout does not. Vertical only, like every other chip row: a
        // wider target would let neighbours overlap and the wrong one win.
        .lsTapTargetTall()
        .sensoryFeedback(.selection, trigger: on)
    }

    private func toggle(_ kind: Ownership) {
        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.6)) {
            if let idx = ownership.firstIndex(of: kind.rawValue) {
                ownership.remove(at: idx)
            } else {
                ownership.append(kind.rawValue)
            }
        }
    }
}

/// Tiny read-only ownership icons for library rows and cover cards.
struct OwnershipBadges: View {
    let ownership: [String]
    var size: CGFloat = 10
    var tint: Color = .secondary

    private var kinds: [Ownership] {
        Ownership.allCases.filter { ownership.contains($0.rawValue) }
    }

    var body: some View {
        if !kinds.isEmpty {
            HStack(spacing: 4) {
                ForEach(kinds, id: \.self) { k in
                    Image(systemName: k.systemImage)
                        .symbolVariant(.fill)
                        .font(.system(size: size))
                }
            }
            .foregroundStyle(tint)
        }
    }
}
