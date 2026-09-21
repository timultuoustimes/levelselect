import SwiftUI
import SwiftData

/// **What you've earned, and what there is to earn.**
///
/// The Journal's fourth lens. Earned badges lead, newest first; the rest
/// follow greyed with what they ask for — the unearned half is the reason to
/// open the tab twice, and it is the app saying what it notices rather than
/// keeping a secret list.
struct BadgesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<EarnedBadge> { $0.deletedAt == nil },
           sort: \EarnedBadge.earnedAt, order: .reverse)
    private var earned: [EarnedBadge]

    private var earnedIDs: [String: Date] {
        Dictionary(earned.map { ($0.badgeID, $0.earnedAt) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                ForEach(Badges.Family.allCases) { family in
                    let rows = Badges.catalogue.filter { $0.family == family }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(family.label)
                                .font(.headline)
                                .padding(.horizontal)
                            ForEach(rows) { badge in
                                BadgeRow(badge: badge, earnedAt: earnedIDs[badge.id])
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LSTheme.accent.opacity(0.16)).frame(width: 54, height: 54)
                Text("\(earned.count)")
                    .font(LSTheme.pixel(20))
                    .foregroundStyle(LSTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(earned.count == 1 ? "One badge earned" : "\(earned.count) badges earned")
                    .font(.title3.weight(.semibold))
                Text("Out of \(Badges.catalogue.count). They come from your library, so the games you brought in count too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

private struct BadgeRow: View {
    let badge: Badges.Definition
    let earnedAt: Date?

    private var isEarned: Bool { earnedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isEarned ? LSTheme.accent.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: badge.symbol)
                    .font(.title3)
                    .foregroundStyle(isEarned ? LSTheme.accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(badge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEarned ? .primary : .secondary)
                Text(badge.earnedBy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let earnedAt {
                Text(earnedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 14))
        .opacity(isEarned ? 1 : 0.65)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isEarned
                            ? "\(badge.title), earned. \(badge.earnedBy)"
                            : "\(badge.title), not yet earned. \(badge.earnedBy)")
    }
}
