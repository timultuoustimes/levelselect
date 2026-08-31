import SwiftUI
import SwiftData

/// Navigation target for a platform's games.
///
/// `ownership` carries the Library filter that was active when the tile was
/// tapped. Without it the shelf counted "Genesis 1" under an Emulated filter
/// and then opened a page listing every Genesis game — the tile and the page
/// disagreeing about the same word. Home passes none, and gets all of them.
struct PlatformRoute: Hashable {
    let platform: String
    var ownership: String? = nil

    /// Grouped by the game's most-PREFERRED owned platform, the same rule the
    /// shelf counts by — so a multi-platform game lands on one console page,
    /// not all of them.
    static func matches(_ game: Game, platform: String, ownership: String?) -> Bool {
        (PlatformPreference.owned(game.platforms) ?? "Other") == platform
        && (ownership == nil || game.ownership.contains(ownership!))
    }
}

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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                                // Two lines, not one. `lineLimit(1)` turned
                                // "Other" and "SNES" into "Oth…" and "SN…" at
                                // accessibility sizes — the shortest names the
                                // app has, so nothing longer stood a chance.
                                Text(PlatformShort.name(g.platform))
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text("\(g.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            // The tile widens with the type rather than
                            // holding a phone-sized 90pt and clipping.
                            .frame(width: typeSize.isAccessibilitySize ? 150 : 90)
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
    var ownership: String? = nil
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]

    private var games: [Game] {
        allGames.filter { PlatformRoute.matches($0, platform: platform, ownership: ownership) }
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
        // Soft, not the default `.hard`. See RootView: iOS 26's scroll edge
        // effect draws a crisp line where content meets a bar unless told
        // otherwise, and one screen fading while the rest cut is worse than
        // either done consistently.
        .scrollEdgeEffectStyle(.soft, for: .top)
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
