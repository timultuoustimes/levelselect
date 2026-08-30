import SwiftUI

/// A slice of a breakdown: what it is, how many, and its colour.
struct PieSlice: Identifiable, Equatable {
    let label: String
    let value: Int
    let color: Color
    var id: String { label }
}

extension PieSlice {
    /// Colours for a breakdown that has none of its own.
    ///
    /// Statuses carry their own colour and keep it. Genres, tags and systems
    /// do not, so they get a fixed palette walked in order — FIXED, not
    /// random or hashed, because a chart whose colours change between
    /// launches teaches nothing. You cannot learn "green is Adventure" if
    /// green is Adventure only today.
    ///
    /// Wraps rather than running out: a library with thirty genres gets
    /// repeats, which is better than blanks.
    static func palette(for rows: [(String, Int)]) -> [PieSlice] {
        let colors: [Color] = [
            Color(hex: "#F5A34D") ?? .orange, Color(hex: "#945CFA") ?? .purple,
            Color(hex: "#4D9BFF") ?? .blue,   Color(hex: "#3FD07A") ?? .green,
            Color(hex: "#FF6B6B") ?? .red,    Color(hex: "#37C6E0") ?? .teal,
            Color(hex: "#D65DB1") ?? .pink,   Color(hex: "#D4D450") ?? .yellow,
            Color(hex: "#8BD450") ?? .mint,   Color(hex: "#FF9F1C") ?? .orange,
            Color(hex: "#7A5CFF") ?? .indigo, Color(hex: "#54C6C6") ?? .cyan,
        ]
        return rows.enumerated().map { index, row in
            PieSlice(label: row.0, value: row.1, color: colors[index % colors.count])
        }
    }
}

/// LevelSelect's pie chart.
///
/// Deliberately not a stock donut. Three things make it the app's own:
///
/// **Segmented, not continuous.** Each slice is drawn with a small angular gap
/// and a gradient across its own colour, so the ring reads as separate pieces
/// rather than one band that changes colour — closer to a dial than to a
/// pie, and it matches the app's other segmented chrome.
///
/// **The total wears the app's face.** Press Start 2P in the middle, the same
/// type as the wordmark and the profile name. It is the third place that face
/// appears and the first inside a chart.
///
/// **Tapping tells you the share.** Tap a slice or its legend row and the
/// centre becomes that slice: its count and its percentage. A static donut
/// makes you estimate angles by eye; this answers the question the chart
/// exists to raise. Tapping again returns to the total.
///
/// The hole is carved by stroke width, not by covering the middle with a
/// disc — so nothing can ever sit on top of the number, which is exactly the
/// failure Tim pointed at in Gamery's.
struct StatsPie: View {
    let slices: [PieSlice]
    let centerTitle: String
    /// Sum of everything, including anything folded into "Other".
    let total: Int

    @State private var selected: String?

    private var sum: Double { max(1, Double(slices.reduce(0) { $0 + $1.value })) }
    private var chosen: PieSlice? { slices.first { $0.label == selected } }

    /// The gap between slices, in turns. Small enough to read as a seam rather
    /// than as missing data, and dropped entirely when a slice is so thin the
    /// gap would swallow it.
    private static let gap = 0.006

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ring
                center
                    .padding(.horizontal, 30)
            }
            .frame(height: 200)
            .animation(.snappy(duration: 0.25), value: selected)

            legend
        }
        .frame(maxWidth: .infinity)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.05), lineWidth: 26)

            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                let start = fraction(before: index)
                let share = Double(slice.value) / sum
                let isChosen = selected == slice.label
                let dim = selected != nil && !isChosen

                Circle()
                    .trim(from: start + (share > Self.gap * 2 ? Self.gap : 0),
                          to: start + share)
                    .stroke(
                        AngularGradient(
                            colors: [slice.color, slice.color.opacity(0.62), slice.color],
                            center: .center),
                        style: StrokeStyle(lineWidth: isChosen ? 34 : 26, lineCap: .butt))
                    .rotationEffect(.degrees(-90))   // start at twelve o'clock
                    .opacity(dim ? 0.28 : 1)
                    .shadow(color: isChosen ? slice.color.opacity(0.5) : .clear, radius: 8)
                    .contentShape(.rect)
                    .onTapGesture { pick(slice) }
            }
        }
        .padding(26)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 3) {
            Text(chosen?.label ?? centerTitle)
                .font(.caption2)
                .foregroundStyle(chosen == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(chosen?.value ?? total)")
                .font(LSTheme.pixel(chosen == nil ? 22 : 20))
            .fontDesign(nil)   // never let an app-wide design override the pixel face
                .foregroundStyle(chosen?.color ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            if let chosen {
                Text(percent(chosen))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .onTapGesture { selected = nil }
    }

    private var legend: some View {
        // Two columns: one column makes a long breakdown taller than the chart
        // it explains, and a wrapping flow leaves ragged gaps.
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 7) {
            ForEach(slices) { slice in
                Button { pick(slice) } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 9, height: 9)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(
                                    selected == slice.label ? 0.9 : 0), lineWidth: 1.5)
                            }
                        Text(slice.label)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text("\(slice.value)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(selected == nil || selected == slice.label ? 1 : 0.45)
            }
        }
    }

    private func pick(_ slice: PieSlice) {
        selected = (selected == slice.label) ? nil : slice.label
    }

    private func percent(_ slice: PieSlice) -> String {
        let share = Double(slice.value) / sum * 100
        // Never round a real slice down to "0%" — a genuine 0.4% is small,
        // not absent, and printing 0 makes the chart look broken.
        return share < 1 ? "<1% of \(total)" : "\(Int(share.rounded()))% of \(total)"
    }

    private func fraction(before index: Int) -> Double {
        slices.prefix(index).reduce(0) { $0 + Double($1.value) } / sum
    }
}
