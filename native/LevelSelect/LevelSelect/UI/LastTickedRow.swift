import SwiftUI
import SwiftData

/// "Where you left off" — the last thing you ticked, and your note about it.
///
/// The app's whole pitch is remembering a game you haven't touched in weeks,
/// and until now it could tell you *how far* you'd got but never *what you
/// were doing*. A percentage doesn't survive three weeks away; "Restore First
/// Spark Generator, 3 weeks ago" does.
///
/// It also teaches the note feature by showing it working. A per-item note was
/// documented only as a promise — that regenerating wouldn't erase it — and
/// lived behind a context menu labeled "Edit", so people never found it.
/// Seeing someone's own note surfaced here, next to the thing it belongs to,
/// explains the field better than a docs paragraph can.
///
/// The timestamp is the record's own `completedAt` — the moment it was
/// ticked, not the moment the row last changed — so editing a note or
/// un-ticking something old can't push it to the front.
struct LastTickedRow: View {
    let game: Game
    /// Home wants the same fact in one line, under a card that's already
    /// carrying a cover, a timer and a play button.
    var compact = false
    @Environment(\.modelContext) private var context

    private var repo: Repository { Repository(context) }

    private struct Recent {
        let name: String
        let note: String?
        let at: Date
        /// Named only when the game has more than one live playthrough —
        /// with two runs listed directly beneath it, "where you left off"
        /// with no run attached is a question, not an answer.
        let playthrough: String?
    }

    private var recent: Recent? {
        guard let playthrough = game.activePlaythrough else { return nil }
        let done = (playthrough.trackerStates ?? [])
            .filter { $0.deletedAt == nil && $0.completed }
        guard let latest = done.max(by: { $0.tickedAt < $1.tickedAt }) else { return nil }

        // Names and notes come from the overlaid read, so a renamed item shows
        // the name its owner chose rather than the generated one.
        for category in repo.trackerCategories(for: game) {
            if let item = category.items.first(where: { $0.id == latest.itemID }) {
                return Recent(name: item.name,
                              note: item.note?.isEmpty == false ? item.note : nil,
                              at: latest.tickedAt,
                              playthrough: game.livePlaythroughs.count > 1
                                  ? playthrough.name : nil)
            }
        }
        return nil
    }

    var body: some View {
        if let recent, compact {
            Label("Left off: \(recent.name)", systemImage: "arrow.uturn.left.circle.fill")
                .font(.caption2)
                .foregroundStyle(LSTheme.accent.opacity(0.9))
                .lineLimit(1)
                .accessibilityLabel("Left off at \(recent.name)")
        } else if let recent {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.left.circle.fill")
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent)
                    Text(recent.playthrough.map { "Where you left off in \($0)" }
                         ?? "Where you left off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(recent.at.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(recent.name)
                    .font(.subheadline.weight(.medium))
                if let note = recent.note {
                    Label(note, systemImage: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Where you left off"
                                + (recent.playthrough.map { " in \($0)" } ?? "")
                                + ": \(recent.name), \(recent.at.formatted(.relative(presentation: .named)))"
                                + (recent.note.map { ". Your note: \($0)" } ?? ""))
        }
    }
}
