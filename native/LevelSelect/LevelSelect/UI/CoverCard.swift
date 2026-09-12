import SwiftUI

/// Box-art card for the horizontal carousels: large cover + title beneath,
/// like the web app's home sections.
struct CoverCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: GameStatus
    let games: [Game]
    var collapsed = false
    var onOpen: (Game) -> Void
    var onSeeAll: () -> Void
    var onToggleCollapse: () -> Void = {}
    var onHide: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The one shelf header, shared with Library and Wishlist. It
            // lived here first and every other tab invented its own; see
            // `ShelfHeader` for what that cost.
            ShelfHeader(
                title: status.sectionTitle,
                count: games.count,
                systemImage: status.systemImage,
                tint: status.color,
                collapsed: collapsed,
                onToggleCollapse: onToggleCollapse,
                onSeeAll: onSeeAll)
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
                        // The shelf breathes and tilts as it scrolls — the
                        // last high-motion effect in the app that ignored
                        // Reduce Motion (Codex K6). Scale and a 3D rotation
                        // are spatial; the fade is not, so the setting drops
                        // the movement and keeps the depth cue rather than
                        // flattening the shelf for everyone.
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.86))
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .rotation3DEffect(
                                    .degrees(reduceMotion ? 0 : phase.value * -12),
                                    axis: (x: 0, y: 1, z: 0))
                        }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            // **The shelf's color, on the shelf.**
            //
            // The status glyph has carried its color in the header for a
            // while, but a title is a line of text — the shelf itself stayed
            // neutral, so Home below the hero read as generic rows. Fable's
            // 5.3: carry it onto the row "so a Paused shelf is orange as a
            // block, not just in its title."
            //
            // A rule rather than a tint on the first cover: the art is the
            // game's, and the one thing this app does not do is paint over it.
            // Sitting in the gutter left of the covers, it also lines the
            // shelves up with each other down the page.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(status.color)
                    .frame(width: 3)
                    .padding(.leading, 6)
                    .padding(.vertical, 4)
                    // Decorative twice over — the header names the shelf, and
                    // the color repeats what the glyph beside it already says.
                    .accessibilityHidden(true)
            }
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
        // Follows the chosen background — it is the ground's hue lifted off
        // it, not a fixed purple panel sitting on someone else's color.
        .background(LSTheme.hero(tintedBy: ThemePalette.backgroundOverride),
                    in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LSTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
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
                        // 56 tall already; only the width was short. Inline so
                        // the hero's Play button beside it does not move.
                        .frame(width: 34, height: 56)
                        .lsTapTargetInline(5)
                }
                .accessibilityLabel("Stop session")
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
                    // soft black blur turns into gray haze.
                    //
                    // The glow above stays: it does the lifting, this does the
                    // shape.
                    .shadow(color: LSTheme.hardStep(under: LSTheme.accent),
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        // The shelf breathes and tilts as it scrolls — the
                        // last high-motion effect in the app that ignored
                        // Reduce Motion (Codex K6). Scale and a 3D rotation
                        // are spatial; the fade is not, so the setting drops
                        // the movement and keeps the depth cue rather than
                        // flattening the shelf for everyone.
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.86))
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .rotation3DEffect(
                                    .degrees(reduceMotion ? 0 : phase.value * -12),
                                    axis: (x: 0, y: 1, z: 0))
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

/// An empty Home shelf, drawn rather than skipped, while the library is new.
///
/// Home hides shelves with nothing on them, which is right for a full library
/// and wrong for the ten minutes after the welcome: someone who has added one
/// game sees a single cover floating in a screen that gives no hint what the
/// rest of it is for. F1's answer was to carry the welcome's promises inside,
/// so the shelf that keeps a promise is the thing that states it.
///
/// It is deliberately NOT a call to action. There is no button and nothing to
/// dismiss — the shelf fills itself the moment a game lands in that status,
/// and until then it is a label on an empty space, the way a real shelf in a
/// room is still a shelf. `StatusCarousel`'s color rule runs down the left of
/// the caption for the same reason, so the empty shelf and the full one are
/// visibly the same object in two states.
struct PromiseShelf: View {
    let status: GameStatus
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // No count and no chevron: zero is not worth printing, and there
            // is nothing to collapse. `ShelfHeader` already treats both as
            // optional, which is why this reads as the same header rather
            // than a lookalike.
            ShelfHeader(
                title: status.sectionTitle,
                count: nil,
                systemImage: status.systemImage,
                tint: status.color,
                collapsed: nil,
                onSeeAll: nil)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.trailing)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(status.color.opacity(0.55))
                        .frame(width: 3)
                        .padding(.leading, 6)
                        .accessibilityHidden(true)
                }
        }
        // One object to VoiceOver: the shelf's name, then what will be on it.
        // Read apart, "Up Next" and a sentence about checklists sound like two
        // unrelated things on a screen that is mostly empty.
        .accessibilityElement(children: .combine)
    }
}
