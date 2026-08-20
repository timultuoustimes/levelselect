import SwiftUI

/// Show critic scores and typical completion times on game pages.
///
/// Off by default. The point is comparing your own verdict with the consensus —
/// which is only interesting if you went looking for it. Someone who didn't
/// shouldn't find a stranger's number sitting next to their five stars.
///
/// It also does the honest thing about cost: with this off, the app never makes
/// the request at all.
struct CriticScoreSettings: View {
    @AppStorage("showCriticScores") private var showCriticScores = false

    var body: some View {
        Section {
            Toggle("Show critic scores", isOn: $showCriticScores)
                .tint(LSTheme.accent)
        } header: {
            Text("Critics & Completion Times")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adds a critic score and a typical time-to-beat under your own rating, so you can see where you land against the consensus.")
                // Said up front rather than discovered: the gaps are the
                // feature working, not the feature failing.
                Text("From IGDB, and only shown when at least \(GameReferenceService.minimumSources) sources agree — so roughly half your library will show a score, and older games usually won't show anything. A figure resting on one stranger's submission is worse than no figure.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
    }
}
