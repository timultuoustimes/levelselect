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
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: game.status.systemImage)
                        .foregroundStyle(game.status.color)
                        .font(.caption)
                    Text(game.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let platform = game.platforms.first {
                        Text("· \(platform)")
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

            if game.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
