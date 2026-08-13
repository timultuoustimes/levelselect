import SwiftUI
import SwiftData

/// Navigation target for a platform's games.
struct PlatformRoute: Hashable { let platform: String }

/// The soft-3D console icon for a platform (falls back to a controller glyph).
struct PlatformIconView: View {
    let platform: String
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let asset = PlatformIcon.assetName(platform) {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: "gamecontroller.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(LSTheme.accent)
                    .padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Home "Systems" shelf — scroll your consoles, tap one to see its games.
struct SystemsRow: View {
    let groups: [(platform: String, count: Int)]
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(LSTheme.accent)
                Text("Systems").font(.title3.bold())
                Text("(\(groups.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(groups, id: \.platform) { g in
                        BouncyTap {
                            onOpen(g.platform)
                        } label: {
                            VStack(spacing: 6) {
                                PlatformIconView(platform: g.platform, size: 54)
                                    .frame(width: 84, height: 84)
                                    .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.07)))
                                Text(PlatformShort.name(g.platform))
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text("\(g.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 90)
                        }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .opacity(phase.isIdentity ? 1 : 0.65)
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

/// All games on a platform (reached by tapping a Systems icon).
struct PlatformGamesView: View {
    let platform: String
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]

    private var games: [Game] {
        allGames.filter { (PlatformPreference.sorted($0.platforms).first ?? "Other") == platform }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                ForEach(games) { game in
                    NavigationLink(value: game) {
                        LibraryGridCell(game: game, size: .medium)
                    }
                    .buttonStyle(PressableCardStyle())
                    .gameContextMenu(game)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle(PlatformShort.name(platform))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    PlatformIconView(platform: platform, size: 24)
                    Text(PlatformShort.name(platform)).font(.headline)
                }
            }
        }
    }
}
