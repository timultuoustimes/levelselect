import WidgetKit
import SwiftUI

struct ShelfCover: View {
    let game: WidgetShelfGame

    var body: some View {
        Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    CoverPoster(image: loadCover(game.coverFileName))
                    if game.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LSWidget.navyDeep)
                            .padding(4)
                            .background(LSWidget.green, in: Circle())
                            .padding(4)
                    }
                }
                Text(game.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }
}

struct NowPlayingShelfView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    private var maxCount: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        let games = Array((snapshot?.nowPlaying ?? []).prefix(maxCount))
        if games.isEmpty {
            EmptyWidget()
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LSWidget.torch)
                    Text("NOW PLAYING")
                        .font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if let total = snapshot?.nowPlaying.count, total > games.count {
                        Text("+\(total - games.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                if family == .systemLarge {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                              spacing: 12) {
                        ForEach(games) { ShelfCover(game: $0) }
                    }
                } else {
                    HStack(spacing: 12) {
                        ForEach(games) { ShelfCover(game: $0) }
                        if games.count < maxCount {
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct NowPlayingShelfWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSNowPlayingShelf", provider: ContinuePlayingProvider()) { entry in
            NowPlayingShelfView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Now Playing")
        .description("Your active games at a glance — tap any to open it.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
