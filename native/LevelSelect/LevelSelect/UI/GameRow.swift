import SwiftUI

struct GameRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 44, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.headline)
                    // A list row can be two lines tall. Clipping the one piece
                    // of text that identifies the row is worse than a taller
                    // row — and at large text sizes two regional editions
                    // become the same truncated prefix.
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Image(systemName: game.status.systemImage)
                        .foregroundStyle(game.status.color)
                        .font(.caption)
                    Text(game.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let platform = PlatformPreference.owned(game.platforms) {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        PlatformIconView(platform: platform, size: 15)
                        Text(PlatformShort.name(platform))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let rating = game.rating {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 5) {
                if game.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                OwnershipBadges(ownership: game.ownership, size: 11)
            }
        }
        .padding(.vertical, 2)
    }
}
