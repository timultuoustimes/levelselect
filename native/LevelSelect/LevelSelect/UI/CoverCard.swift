import SwiftUI

/// Box-art card for the horizontal carousels: large cover + title beneath,
/// like the web app's home sections.
struct CoverCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 108, height: 144)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if game.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial, in: .circle)
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)

            Text(game.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 108, alignment: .leading)
    }
}

/// A titled horizontal carousel of covers, with count + "See all".
struct StatusCarousel: View {
    let status: GameStatus
    let games: [Game]
    var collapsed = false
    var onOpen: (Game) -> Void
    var onSeeAll: () -> Void
    var onToggleCollapse: () -> Void = {}
    var onHide: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { onToggleCollapse() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                }
                .buttonStyle(.plain)
                Image(systemName: status.systemImage)
                    .foregroundStyle(status == .playing ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
                Text(status.sectionTitle)
                    .font(.title3.bold())
                Text("(\(games.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !collapsed {
                    Button("See all") { onSeeAll() }
                        .font(.subheadline)
                        .foregroundStyle(LSTheme.accent)
                        .buttonStyle(.plain)
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
                    Button(role: .destructive) {
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

    var body: some View {
        HStack(spacing: 14) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 76, height: 101)
                .overlay { CoverShine() }
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)

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
                    Text(platform)
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

            Spacer(minLength: 0)

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
                            Text(active.state == .running ? "Pause" : "Resume")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .background(LSTheme.accent.opacity(0.16), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(LSTheme.accent.opacity(0.6), lineWidth: 1))
                    .foregroundStyle(LSTheme.accent)
                }
            } else {
                Button(action: onPlay) {
                    VStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Play").font(.caption.weight(.semibold))
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .background(.green.opacity(0.16), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.6), lineWidth: 1))
                .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(LSTheme.heroGradient, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LSTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}
