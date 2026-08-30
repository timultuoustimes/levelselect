import SwiftUI

/// The persistent stats header for a game: how long you've played it, how
/// many times you've sat down with it, how many times you've finished it.
///
/// The web app had this and the native app lost it. Here the numbers lived
/// inside the Sessions section, which meant collapsing Sessions — a section
/// people collapse precisely because the list of sittings is long — made a
/// game's total playtime unreachable. Worse, the number in there described
/// one playthrough, so a second playthrough made the figure on screen quietly
/// smaller than the truth.
///
/// Everything here is a lifetime total across every live playthrough,
/// finished ones included, because "how long have I spent on this game?" has
/// never meant "since the most recent restart".
///
/// The whole row is hideable. Timing your play is opt-in in this app; someone
/// who never starts a timer should not have a permanent 0h card at the top of
/// every game page telling them so.
struct GameStatsRow: View {
    let game: Game
    /// Runs get a card only on games that log them, so the row doesn't grow a
    /// fourth column of zeroes on the other several hundred.
    let showsRuns: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // A running timer is part of the total, so the card counts up with it
        // rather than showing a number that's wrong until the next redraw.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            layout {
                card("Played", playedText(asOf: ctx.date), "clock")
                card("Sessions", "\(game.lifetimeSessionCount)", "hourglass")
                card("Beaten", "\(game.liveCompletionEvents.count)", "flag.checkered")
                if showsRuns {
                    card("Runs", "\(game.lifetimeRunCount)", "flag.fill")
                }
            }
        }
    }

    /// `Format.duration` bottoms out at "0s", which reads like a stopwatch
    /// that failed rather than a game you haven't timed yet.
    private func playedText(asOf now: Date) -> String {
        let played = game.lifetimePlaytime(asOf: now)
        return played < 60 ? (played > 0 ? "<1m" : "—") : Format.duration(played)
    }

    /// Four cards sharing a 393pt phone give each about 90pt, which is fine
    /// for "12h 30m" at caption size and not fine at accessibility sizes —
    /// where the numbers matter more, not less. So they stack instead.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private func card(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        // One label per card, so VoiceOver says "Played, 12 hours 30 minutes"
        // instead of reading the icon, the title and the number as three
        // unrelated things.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
