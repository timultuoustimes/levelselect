import SwiftUI

/// Box-art card for the horizontal carousels: large cover + title beneath,
/// like the web app's home sections.
struct CoverCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverThumb(urlString: game.displayCoverURLString)
                .frame(width: 108, height: 144)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if game.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .padding(5)
                            .glassEffect(.regular, in: .circle)
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)

            // Two lines in a 108pt cell fits "Super Metroid" at normal type
            // and truncates it to "Super Metr…" at accessibility sizes. The
            // cell widens and takes a third line rather than clipping the one
            // piece of text on a cover card that identifies the game.
            Text(game.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: typeSize.isAccessibilitySize ? 168 : 108, alignment: .leading)
    }
}

/// A titled horizontal carousel of covers, with count + "See all".
struct StatusCarousel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let status: GameStatus
    let games: [Game]
    var collapsed = false
    var onOpen: (Game) -> Void
    var onSeeAll: () -> Void
    var onToggleCollapse: () -> Void = {}
    var onHide: (() -> Void)?

    private var collapseChevron: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { onToggleCollapse() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: some View {
        Image(systemName: status.systemImage)
            .foregroundStyle(status == .playing ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
    }

    private var seeAllButton: some View {
        Button("See all") { onSeeAll() }
            .font(.subheadline)
            .foregroundStyle(LSTheme.accent)
            .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Five things in one row — chevron, icon, title, count, See all —
            // works until the title is 50pt, at which point "Now Playing"
            // truncates to "Now" and the action is pushed off the edge. At
            // accessibility sizes the row splits: the shelf identifies itself
            // on one line, and See all becomes its own control underneath
            // rather than competing for the same horizontal space.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            collapseChevron
                            statusIcon
                            // Title and count as ONE string here. Kept apart
                            // they became two stacked lines, because at this
                            // size each is wide enough to claim a row of its
                            // own — "Now Playing" then "(2)" then "See all",
                            // three lines to say one thing.
                            Text("\(status.sectionTitle) (\(games.count))")
                                .font(.title3.bold())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !collapsed { seeAllButton }
                    }
                } else {
                    HStack(spacing: 6) {
                        collapseChevron
                        statusIcon
                        Text(status.sectionTitle)
                            .font(.title3.bold())
                        Text("(\(games.count))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !collapsed { seeAllButton }
                    }
                }
            }
            .padding(.horizontal)
            .contentShape(.rect)
            .contextMenu {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { onToggleCollapse() }
                } label: {
                    Label(collapsed ? "Expand" : "Collapse",
                          systemImage: collapsed ? "chevron.down" : "chevron.right")
                }
                if let onHide {
                    // Hiding is about Home only. The games stay in the library,
                    // still sortable and filterable by this status — "I don't
                    // want to look at 60 backlog games every time I open the
                    // app" is not the same wish as "forget I own them".
                    // Not `.destructive`. Red is reserved for losing data;
                    // this shelf comes back from Hidden from Home at the
                    // bottom of this very screen, and nothing about the games
                    // in it changes.
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { onHide() }
                    } label: { Label("Hide from Home", systemImage: "eye.slash") }
                }
            }

            if !collapsed {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(games) { game in
                        BouncyTap {
                            onOpen(game)
                        } label: {
                            CoverCard(game: game)
                        }
                        .gameContextMenu(game)
                        // Covers breathe + tilt like a shelf as they scroll.
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0))
                        }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

/// Continue Playing hero: gradient card, cover, context line, Play button.
struct ContinueHeroCard: View {
    let game: Game
    var onPlay: () -> Void
    /// Present when the card is allowed to control a live session. Home
    /// passes these; other callers get the plain Play button.
    var onPauseResume: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil

    private var playthrough: Playthrough? {
        game.activePlaythrough
    }

    private var active: Session? { playthrough?.activeSession }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes this was a fixed HStack and it inverted its
        // own hierarchy: the 76pt cover stayed 76pt while "Super Nintendo
        // Entertainment System" wrapped to five lines and hyphenated
        // ("Entertain-ment") in the strip left between two fixed objects.
        //
        // Stacked, the cover and the action share one row — they are the two
        // things that DON'T grow with type — and the text gets the whole card
        // width underneath. Nothing is hidden and no size is capped; the
        // component changes shape instead.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        cover(width: 96, height: 128)
                        Spacer(minLength: 0)
                        actions
                    }
                    details
                }
            } else {
                HStack(spacing: 14) {
                    cover(width: 76, height: 101)
                    details
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(14)
        .background(LSTheme.heroGradient, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LSTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        CoverThumb(urlString: game.displayCoverURLString)
            .frame(width: width, height: height)
            .overlay { CoverShine() }
            .clipShape(.rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(game.name)
                .font(.headline)
                .lineLimit(2)

            // Where you were, directly under the title. This is the line that
            // actually gets you back into the game, and it used to sit fourth,
            // under two lines of bookkeeping — so the card answered "how long
            // have I been at this" before "where was I".
            LastTickedRow(game: game, compact: true)

            if let active {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Label(Format.clock(active.elapsed(asOf: ctx.date)),
                          systemImage: active.state == .running ? "record.circle" : "pause.circle")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(active.state == .running ? .green : .orange)
                }
            } else if let last = playthrough?.lastPlayedAt {
                Text("Last played \(last, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let platform = game.platforms.first {
                // The short name, same as the game page. This card was the one
                // place still printing "Super Nintendo Entertainment System"
                // in full — which is how it came to hyphenate into
                // "Entertain-ment" across five lines at accessibility sizes.
                // Shortening the string is the real fix; the stacked layout
                // just stops the long ones being squeezed.
                Text(PlatformShort.name(platform))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let total = playthrough?.totalPlaytime() ?? 0
            if total > 0 {
                Text(Format.duration(total) + " played")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        }
    }

    @ViewBuilder
    private var actions: some View {
        // A running timer is the thing you most want to act on, and it
        // used to be unreachable from here: the button still said Play,
        // and stopping meant navigating into the game. When a session is
        // live the primary action becomes pause/resume, with stop beside
        // it — small, because ending a session by mis-tap is worse than
        // an extra tap.
        if let active, let onPauseResume, let onStop {
            HStack(spacing: 8) {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .frame(width: 34, height: 56)
                }
                .buttonStyle(.plain)
                .background(.red.opacity(0.14), in: .rect(cornerRadius: 10))
                .foregroundStyle(.red.opacity(0.9))
                .accessibilityLabel("Stop session")

                Button(action: onPauseResume) {
                    VStack(spacing: 4) {
                        Image(systemName: active.state == .running ? "pause.fill" : "play.fill")
                        // At accessibility sizes the caption can't fit the
                        // fixed square — the glyph alone reads better than
                        // "P…", and the label below says the word.
                        if !typeSize.isAccessibilitySize {
                            Text(active.state == .running ? "Pause" : "Resume")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(active.state == .running ? "Pause" : "Resume")
                .background(LSTheme.accent.opacity(0.16), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LSTheme.accent.opacity(0.6), lineWidth: 1))
                .foregroundStyle(LSTheme.accent)
            }
        } else {
            Button(action: onPlay) {
                VStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    if !typeSize.isAccessibilitySize {
                        Text("Play").font(.caption.weight(.semibold))
                    }
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
            // FILLED, and in the accent rather than green.
            //
            // Two reasons. It is the most important control on Home and it was
            // the lightest thing in the card — a hairline outline beside a big
            // filled panel, which is what a *secondary* action looks like.
            //
            // And green meant two opposite things: this button ("start"), and
            // the running-timer readout above ("already going"). Green is now
            // reserved for running, so anywhere in the app it says one thing —
            // a timer is live.
            // A gradient, a lit top edge and a colored shadow — a flat
            // rectangle of accent read as a disabled block rather than the
            // most pressable thing on the page. The depth is what says
            // "button"; the fill is what says "primary".
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [LSTheme.accent, LSTheme.accent.opacity(0.78)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    // Quiet. The glow is here to lift the button off the
                    // card, not to announce itself — and it vanishes the
                    // moment a timer starts and Pause takes over, so a loud
                    // one reads as something breaking rather than a state
                    // change.
                    .shadow(color: LSTheme.accent.opacity(0.22), radius: 6, y: 3)
                    // A HARD step, where the blur used to be.
                    //
                    // Same reasoning as the wordmark and the username, applied
                    // to an object rather than type: this app's visual
                    // language is pixel art, and a gaussian blur is the one
                    // thing pixel art never has. A solid offset in a darkened
                    // accent reads as the button standing on its own shadow —
                    // which is also more legible on a light ground, where a
                    // soft black blur turns into grey haze.
                    //
                    // The glow above stays: it does the lifting, this does the
                    // shape.
                    .shadow(color: LSTheme.accent.mix(with: .black, by: 0.55),
                            radius: 0, y: 3)
            }
            .foregroundStyle(LSTheme.onAccent)
        }
    }
}

/// Home's "Recently Beaten" shelf.
///
/// Deliberately simpler than `StatusCarousel`: no collapse, no "hide from
/// Home", no "See all". It is a window rather than a category — it empties
/// itself after a month, so the controls for living with a permanent shelf
/// would be controls for a shelf that is already leaving. The permanent
/// record is Library's Finished section.
struct RecentlyBeatenShelf: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let games: [Game]
    var onOpen: (Game) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flag.pattern.checkered")
                    .foregroundStyle(LSTheme.accent)
                Text("Recently Beaten")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("(\(games.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(games) { game in
                        BouncyTap {
                            onOpen(game)
                        } label: {
                            CoverCard(game: game)
                        }
                        .gameContextMenu(game)
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0))
                        }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
