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

    @AppStorage(BadgeAwarder.summaryPendingKey) private var summaryPending = false
    @State private var celebrate = 0
    @State private var showing: ShownBadge?

    /// The sheet's subject. `Badges.Definition` is `Identifiable` by its id,
    /// but the sheet also needs when it was earned.
    struct ShownBadge: Identifiable {
        let badge: Badges.Definition
        let earnedAt: Date?
        var id: String { badge.id }
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
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, badge in
                                BadgeRow(badge: badge, earnedAt: earnedIDs[badge.id],
                                         phase: Double(index) * 0.17) {
                                    showing = ShownBadge(badge: badge, earnedAt: earnedIDs[badge.id])
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        // The backfill is deliberately silent — fourteen celebrations at once
        // is a cannon. But it still happened, so the first visit here says so
        // once, with the confetti it skipped (Tim, 09-21).
        .overlay { ConfettiBurst(trigger: celebrate).allowsHitTesting(false) }
        .sheet(item: $showing) { shown in
            BadgeDetailSheet(badge: shown.badge, earnedAt: shown.earnedAt)
        }
        // Keyed on the count, not plain `.task`: on first appearance the
        // query hasn't loaded yet, so a one-shot task saw an empty ledger and
        // never celebrated (09-21).
        .task(id: earned.count) {
            // Read the flag rather than trusting `@AppStorage`'s cache: it is
            // written by the awarder, which may have run before this view was
            // made, and SwiftUI does not always see a write it did not make.
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: BadgeAwarder.summaryPendingKey), !earned.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(350))
            celebrate += 1
            defaults.set(false, forKey: BadgeAwarder.summaryPendingKey)
            summaryPending = false
        }
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
                Text(summaryPending
                     ? "Earned from the library you already had — each dated to when you did it."
                     : "Out of \(Badges.catalogue.count). They come from your library, so the games you brought in count too.")
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
    var phase: Double = 0
    var open: () -> Void = {}

    private var isEarned: Bool { earnedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            BadgeArt(badge: badge, size: 46, shimmers: isEarned, phase: phase)
                // Not yet earned reads as unlit rather than absent: you can
                // see what it looks like, which is half of wanting it.
                .saturation(isEarned ? 1 : 0)
                .opacity(isEarned ? 1 : 0.5)
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
        // Tap one and it opens big enough to look at. A badge you earned is
        // worth picking up and turning over.
        .contentShape(.rect)
        .onTapGesture { open() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isEarned
                            ? "\(badge.title), earned. \(badge.earnedBy)"
                            : "\(badge.title), not yet earned. \(badge.earnedBy)")
    }
}

/// **The badge, big.**
///
/// The list is a ledger; this is the object. Large art with the light moving
/// across it, its name, what earned it, and when — or, if you haven't earned
/// it yet, what it would take.
private struct BadgeDetailSheet: View {
    let badge: Badges.Definition
    let earnedAt: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                BadgeArt(badge: badge, size: 220, shimmers: true)
                    .saturation(earnedAt == nil ? 0 : 1)
                    .opacity(earnedAt == nil ? 0.6 : 1)
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                VStack(spacing: 8) {
                    Text(badge.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(badge.earnedBy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let earnedAt {
                        Label {
                            Text(earnedAt, format: .dateTime.month(.wide).day().year())
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LSTheme.accent)
                        .padding(.top, 4)
                    } else {
                        Text("Not earned yet")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .lsBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationTitle(Badges.Family.allCases.first { $0 == badge.family }?.label ?? "Badge")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .lsSheet([.medium, .large])
    }
}
