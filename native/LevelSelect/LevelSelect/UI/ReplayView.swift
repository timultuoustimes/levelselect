import SwiftUI
import SwiftData

/// **A period of your own library, read back to you.**
///
/// Not another list of numbers — the Charts lens is already that, and it is
/// the surface this was specced beside. A Replay is a designed artefact you
/// open, look at, and close, which is why it is a card there rather than a
/// fifth lens: it is an occasion, not a place you live.
///
/// Everything on it is computed on the device from records already in the
/// store. Nothing is sent anywhere to make it.
struct ReplayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var spans: [Replay.Span] = []
    @State private var chosen = 0
    @State private var replay: Replay?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if spans.count > 1 { spanPicker }
                    if let replay, !replay.isEmpty {
                        headline(replay)
                        if !replay.played.isEmpty { topGames(replay) }
                        if !replay.finished.isEmpty { finishes(replay) }
                        if !replay.carried.isEmpty { carried(replay) }
                        if !replay.badges.isEmpty { badges(replay) }
                        footnote(replay)
                    } else {
                        empty
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .lsBackground()
            .navigationTitle(replay.map { $0.span.title() } ?? "Replay")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            spans = ReplayBuilder.availableSpans(in: context)
            rebuild()
        }
        .onChange(of: chosen) { _, _ in rebuild() }
    }

    private func rebuild() {
        guard spans.indices.contains(chosen) else {
            replay = nil
            return
        }
        replay = Replay.make(spans[chosen], from: ReplayBuilder.source(in: context))
    }

    private var spanPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                    let isChosen = index == chosen
                    Text(span.title())
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        // `accentFill` under `onAccent`, never `accent` under
                        // a hardcoded black: the chosen chip has to stay
                        // readable on every palette, light and dark.
                        .background(isChosen ? LSTheme.accentFill : LSTheme.cardFill,
                                    in: .capsule)
                        .foregroundStyle(isChosen ? LSTheme.onAccent : .primary)
                        .contentShape(.capsule)
                        .onTapGesture { chosen = index }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// The one sentence the whole screen is for.
    private func headline(_ replay: Replay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Format.duration(replay.totalSeconds))
                .font(LSTheme.pixel(34))
                .foregroundStyle(LSTheme.accent)
            Text(sentence(replay))
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                stat("\(replay.daysPlayed)", replay.daysPlayed == 1 ? "day" : "days")
                stat("\(replay.gamesPlayedCount)", replay.gamesPlayedCount == 1 ? "game" : "games")
                stat("\(replay.sessionCount)", replay.sessionCount == 1 ? "session" : "sessions")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
    }

    /// Written as a remark rather than a readout — the numbers are above it.
    private func sentence(_ replay: Replay) -> String {
        guard let lead = replay.played.first else {
            return "You kept the record even where you didn't play."
        }
        if replay.finished.count >= 2 {
            return "Mostly \(lead.name), and you finished \(replay.finished.count) games."
        }
        if let finish = replay.finished.first {
            // "Mostly Hollow Knight, and you finished Hollow Knight" — the
            // usual case, since the game you played most is very often the
            // one you finished, and saying the name twice reads like a fault.
            return finish.id == lead.id
                ? "Mostly \(lead.name), and you finished it."
                : "Mostly \(lead.name), and you finished \(finish.name)."
        }
        return "Mostly \(lead.name)."
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LSTheme.accent.opacity(0.14), in: .capsule)
    }

    private func topGames(_ replay: Replay) -> some View {
        section("What you played") {
            let top = Array(replay.played.prefix(5))
            let most = top.first?.seconds ?? 1
            VStack(spacing: 10) {
                ForEach(top) { game in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(game.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.duration(game.seconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        // A bar against the period's own leader, so the shape
                        // is of this year rather than of the library.
                        GeometryReader { proxy in
                            Capsule()
                                .fill(LSTheme.accentFill)
                                .frame(width: max(3, proxy.size.width * (game.seconds / most)))
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private func finishes(_ replay: Replay) -> some View {
        section(replay.finished.count == 1 ? "What you finished"
                                           : "What you finished — \(replay.finished.count)") {
            VStack(spacing: 8) {
                ForEach(replay.finished) { finish in
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(LSTheme.accent)
                        Text(finish.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(finish.date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Hours you told the app belonged to this year, kept visibly apart from
    /// the timed ones — they are a recollection, not a record.
    private func carried(_ replay: Replay) -> some View {
        section("Also this year, from before you tracked") {
            VStack(spacing: 8) {
                ForEach(replay.carried) { game in
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(LSTheme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(game.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            // A range names itself on every year it touches,
                            // so nobody reads it as this year's alone.
                            if game.isRange {
                                Text("across \(game.span)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(Format.duration(game.seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Imported totals you placed in \(replay.span.title()). They aren't in the hours above, because they have no days in them — and a range is shown whole on every year it covers rather than divided between them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func badges(_ replay: Replay) -> some View {
        section(replay.badges.count == 1 ? "A badge you earned"
                                         : "\(replay.badges.count) badges you earned") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                      spacing: 8) {
                ForEach(replay.badges) { badge in
                    VStack(spacing: 4) {
                        BadgeArt(badge: badge, size: 40)
                        Text(badge.title)
                            .font(.system(size: 9, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The quieter facts, and the line about where this was made.
    private func footnote(_ replay: Replay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let busiest = replay.busiestDay {
                line("Your longest day was \(busiest.day.formatted(.dateTime.month(.wide).day())) — \(Format.duration(busiest.seconds)).")
            }
            if replay.longestSession > 0 {
                line("The longest single sitting was \(Format.duration(replay.longestSession)).")
            }
            if replay.added > 0 {
                line("\(replay.added) game\(replay.added == 1 ? "" : "s") joined the library.")
            }
            if replay.memoriesWritten > 0 {
                line("You wrote \(replay.memoriesWritten) memor\(replay.memoriesWritten == 1 ? "y" : "ies").")
            }
            Text("Made on this device, from your own records. Nothing left it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to replay yet")
                .font(.title3.weight(.semibold))
            Text("Time a session, finish something, or write a memory, and this fills in on its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
    }
}

/// The door into a Replay, at the top of the Charts lens.
///
/// It names the period and one true thing about it, so opening it is a choice
/// rather than a gamble — and it says nothing at all when there is nothing to
/// say, rather than offering a recap of a month you didn't play.
struct ReplayEntryCard: View {
    @Environment(\.modelContext) private var context
    @State private var replay: Replay?
    @State private var showing = false

    var body: some View {
        Group {
            if let replay, !replay.isEmpty {
                card(replay)
            } else {
                // **A sliver, not nothing.** This card sits in a `LazyVStack`,
                // which never realizes a child that lays out to zero — so a
                // plain `EmptyView` here meant the `.task` below never ran and
                // the card never appeared at all (09-21).
                Color.clear.frame(height: 1)
            }
        }
        .task {
            let spans = ReplayBuilder.availableSpans(in: context)
            guard let first = spans.first else { return }
            replay = Replay.make(first, from: ReplayBuilder.source(in: context))
        }
        .sheet(isPresented: $showing) { ReplayView().lsSheet([.large]) }
    }

    private func card(_ replay: Replay) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LSTheme.accent.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LSTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(replay.span.title())
                    .font(.headline)
                Text("\(Format.duration(replay.totalSeconds)) across \(replay.daysPlayed) day\(replay.daysPlayed == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onTapGesture { showing = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replay: \(replay.span.title())")
        .accessibilityAddTraits(.isButton)
    }
}
