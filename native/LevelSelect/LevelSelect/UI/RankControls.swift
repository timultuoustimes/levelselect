import SwiftUI

/// How a ranked tracker item should be drawn.
///
/// The built-in schemas (Hades and friends) carry `maxRank` but no display
/// hint, so everything used to fall through to a `Stepper` — a `+`/`−` pair
/// with a small "0/5" beside it. That's accurate and unreadable: you can't see
/// at a glance how far along a row is, and a column of steppers reads as a
/// form rather than a collection.
///
/// These are tap-to-set instead. Tapping pip 3 sets rank 3; tapping the pip
/// you're already on steps back down, so a mis-tap costs one tap to undo.
enum RankDisplay {
    case pips        // small dots — ranks up to 5
    case hearts      // keepsake affinity, which the game itself draws as hearts
    case numbered    // numbered boxes — better past ~6 ranks than a row of dots
    case stepper     // fallback for anything unusually long

    /// Pick a display from the schema's explicit hint, else from the shape of
    /// the data. Inference matters because the built-in schemas predate the
    /// hint and shouldn't need rewriting to look right.
    static func resolve(explicit: String?, categoryName: String, maxRank: Int) -> RankDisplay {
        switch explicit?.lowercased() {
        case "pips":     return .pips
        case "hearts":   return .hearts
        case "numbered": return .numbered
        case "stepper":  return .stepper
        default: break
        }
        // Hades draws keepsake affinity as hearts, so match the source game.
        if categoryName.localizedCaseInsensitiveContains("keepsake") { return .hearts }
        if maxRank <= 5  { return .pips }
        if maxRank <= 12 { return .numbered }
        return .stepper
    }
}

/// Tap-to-set rank control. `onSet` receives the new rank; tapping the current
/// rank passes `current - 1` so the control can go down as well as up.
struct RankPicker: View {
    let display: RankDisplay
    let current: Int
    let maxRank: Int
    /// Optional per-rank names ("Base", "Upgraded"), shown beside the control.
    let rankNames: [String]?
    let tint: Color
    var onSet: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch display {
            case .pips:     pips(symbol: "circle.fill", size: 11)
            case .hearts:   pips(symbol: "heart.fill", size: 13)
            case .numbered: numbered
            case .stepper:  stepper
            }

            if let label = rankLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var rankLabel: String? {
        guard let names = rankNames, current > 0, current <= names.count else { return nil }
        return names[current - 1]
    }

    private func pips(symbol: String, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(1...maxRank, id: \.self) { rank in
                Button {
                    onSet(rank == current ? rank - 1 : rank)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: size))
                        .foregroundStyle(rank <= current ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rank \(rank) of \(maxRank)")
                .accessibilityAddTraits(rank <= current ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.18), value: current)
    }

    private var numbered: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRank, id: \.self) { rank in
                Button {
                    onSet(rank == current ? rank - 1 : rank)
                } label: {
                    Text("\(rank)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(rank <= current ? tint.opacity(0.9) : Color.white.opacity(0.06))
                        )
                        .foregroundStyle(rank <= current ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rank \(rank) of \(maxRank)")
            }
        }
        .animation(.snappy(duration: 0.18), value: current)
    }

    private var stepper: some View {
        Stepper(value: Binding(get: { current }, set: { onSet($0) }), in: 0...maxRank) {
            Text("\(current)/\(maxRank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .controlSize(.mini)
    }
}

/// Some schema descriptions carry a second variant inline, the way Hades'
/// Mirror of Night talents do:
///
///     "Revive once per chamber with health restored. (Alt: Revive once per
///      run with more health)"
///
/// Rendering that as one long run-on hides the choice the game is actually
/// offering. This splits it and puts the alternative behind an "Alt" chip.
struct AltDescription: View {
    let text: String
    let tint: Color
    @State private var showingAlt = false

    /// Returns (base, alt) when the description contains an "(Alt: …)" clause.
    static func split(_ text: String) -> (base: String, alt: String)? {
        guard let range = text.range(of: "(Alt:", options: .caseInsensitive) else { return nil }
        let base = String(text[text.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        var alt = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if alt.hasSuffix(")") { alt.removeLast() }
        return (base, alt.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        if let parts = Self.split(text) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.base)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showingAlt.toggle() }
                    } label: {
                        Text("Alt")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(showingAlt ? tint.opacity(0.25) : Color.white.opacity(0.07))
                            )
                            .overlay(Capsule().strokeBorder(tint.opacity(showingAlt ? 0.6 : 0.25)))
                            .foregroundStyle(showingAlt ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingAlt ? "Hide alternative" : "Show alternative")
                }
                if showingAlt {
                    Text(parts.alt)
                        .font(.caption)
                        .foregroundStyle(tint.opacity(0.85))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        RankPicker(display: .pips, current: 3, maxRank: 5, rankNames: nil,
                   tint: LSTheme.purple) { _ in }
        RankPicker(display: .hearts, current: 2, maxRank: 3, rankNames: nil,
                   tint: .pink) { _ in }
        RankPicker(display: .numbered, current: 4, maxRank: 8, rankNames: nil,
                   tint: LSTheme.purple) { _ in }
        AltDescription(
            text: "Revive once per chamber with health restored. (Alt: Revive once per run with more health)",
            tint: LSTheme.purple)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LSTheme.background)
}
