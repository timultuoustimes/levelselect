import SwiftUI

/// Collapsible page section with a persisted expansion state — per Tim:
/// sections collapsible so game pages stay scannable.
///
/// Pass `scope` (a game's id) to persist per game. Without it the key is
/// shared library-wide — which was the original behaviour *by accident*:
/// keying on the title alone meant collapsing Tracker on one game collapsed
/// it on every game. A game with a huge tracker and a game with none want
/// different defaults, so game pages pass their game; a genuinely global
/// surface may omit the scope deliberately.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    var defaultExpanded = true
    @ViewBuilder var content: Content

    @AppStorage private var expanded: Bool

    init(_ title: String, icon: String, defaultExpanded: Bool = true,
         scope: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.defaultExpanded = defaultExpanded
        self.content = content()
        let key = scope.map { "section.\($0).\(title)" } ?? "section.\(title)"
        _expanded = AppStorage(wrappedValue: defaultExpanded, key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Simple flow layout for chip rows (wraps to as many lines as needed).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var height: CGFloat = 0 }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}

/// Editable chip group: removable chips + an add field.
struct EditableChips: View {
    let title: String
    @Binding var values: [String]
    var tint: Color = LSTheme.accent
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if !values.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        Chip(text: value, tint: tint) {
                            values.removeAll { $0 == value }
                        }
                    }
                }
            }
            TextField("Add \(title.lowercased())…", text: $newValue)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    let value = newValue.trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty, !values.contains(value) {
                        values.append(value)
                    }
                    newValue = ""
                }
        }
    }
}

/// Metadata chip.
struct Chip: View {
    let text: String
    var tint: Color = LSTheme.accent
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.18), in: .capsule)
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .foregroundStyle(.primary)
    }
}
