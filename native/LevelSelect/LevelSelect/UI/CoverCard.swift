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
    var onOpen: (Game) -> Void
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status == .playing ? AnyShapeStyle(LSTheme.purple) : AnyShapeStyle(.secondary))
                Text(status.sectionTitle)
                    .font(.title3.bold())
                Text("(\(games.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("See all") { onSeeAll() }
                    .font(.subheadline)
                    .foregroundStyle(LSTheme.purple)
                    .buttonStyle(.plain)
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

/// Continue Playing hero: gradient card, cover, context line, Play button.
struct ContinueHeroCard: View {
    let game: Game
    var onPlay: () -> Void

    private var playthrough: Playthrough? {
        (game.playthroughs ?? []).first { $0.deletedAt == nil }
    }

    var body: some View {
        HStack(spacing: 14) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 76, height: 101)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)

                if let active = playthrough?.activeSession {
                    Label(active.state == .running ? "Session in progress" : "Session paused",
                          systemImage: active.state == .running ? "record.circle" : "pause.circle")
                        .font(.caption)
                        .foregroundStyle(active.state == .running ? .green : .orange)
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
        .padding(14)
        .background(LSTheme.heroGradient, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LSTheme.purple.opacity(0.35), lineWidth: 1)
        )
    }
}
