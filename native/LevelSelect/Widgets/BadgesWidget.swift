import WidgetKit
import SwiftUI

/// **What you've earned, on the Home Screen.**
///
/// The Journal's Badges lens, at a glance: how many of the catalogue you have
/// and the most recent ones. Symbols in the accent, the same as the app draws
/// them — when there is art worth keeping, it lands here without the layout
/// changing (spec, 09-21).
///
/// It grows with the family rather than switching layout: the count line is
/// always there, and the grid takes whatever rows are left.
struct BadgesWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var badges: [WidgetBadge] { snapshot?.badges ?? [] }
    private var earned: Int { snapshot?.completedBadgeCount ?? 0 }
    private var total: Int { snapshot?.badgesTotal ?? 0 }

    /// Columns and rows per family. The portrait extra-large is tall and
    /// narrow, so it keeps the medium's column count and spends the space on
    /// rows — which is the point of a portrait widget.
    private var shape: (columns: Int, rows: Int) {
        switch family {
        case .systemSmall: (3, 2)
        case .systemMedium: (6, 2)
        case .systemLarge: (6, 4)
        default: (5, 8)     // .systemExtraLargePortrait, iOS 27
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            header
            if badges.isEmpty {
                // Not an error state. Nobody has earned anything on the day
                // they install, and "0" over an empty grid reads as a fault.
                Text("Play something and they start arriving.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetShared.badgesURL)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LSWidget.accent)
            Text(earned == 1 ? "1 BADGE" : "\(earned) BADGES")
                .font(.system(size: 10, weight: .bold)).tracking(0.7)
                .foregroundStyle(.primary)
            if total > 0 {
                Text("of \(total)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // The newest one's date, where there is room for it — a badge is
            // a thing that happened on a day.
            if family != .systemSmall, let latest = badges.first {
                Text(latest.earnedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var grid: some View {
        let shown = Array(badges.prefix(shape.columns * shape.rows))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: shape.columns),
            spacing: 6
        ) {
            ForEach(shown) { badge in
                ZStack {
                    Circle().fill(LSWidget.accent.opacity(0.16))
                    Image(systemName: badge.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LSWidget.accent)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension WidgetSnapshot {
    /// How many badges are earned.
    ///
    /// `badges` is capped at twelve for the file's sake, so it cannot be
    /// counted for the total — a fourteenth badge would make the widget say
    /// twelve. The ledger's own count travels in `badgesEarnedCount`, and
    /// this falls back to the list only for a snapshot written before that
    /// field existed.
    var completedBadgeCount: Int {
        badgesEarnedCount > 0 ? badgesEarnedCount : badges.count
    }
}

struct BadgesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Badges", provider: ContinuePlayingProvider()) { entry in
            BadgesWidgetView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Badges")
        .description("What you've earned, and how much of the set that is.")
        .supportedFamilies(Self.families)
    }

    /// The portrait extra-large is iOS 27's, and the only portrait family
    /// there is — it appears on iPad and the Mac's desktop, not on iPhone.
    private static var families: [WidgetFamily] {
        var all: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 27.0, macOS 27.0, *) { all.append(.systemExtraLargePortrait) }
        return all
    }
}
