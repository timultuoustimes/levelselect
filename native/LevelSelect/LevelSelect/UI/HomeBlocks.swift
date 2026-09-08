import SwiftUI
import SwiftData

/// The blocks Home is composed of that did not exist before it was
/// composable: the display case, a pinned collection's own shelf, and the
/// empty case a new library shows before it has any consoles to display.
/// `StatusCarousel`, `SystemsRow` and `CollectionShelf` already existed and
/// are used as they are.

// MARK: - The display case

/// The consoles you own, as the display in the photographs: a three-wide
/// grid, every tile visible, no scrolling. Tim, 2026-08-31, with four
/// pictures of real game rooms: *"the consoles are the display — lit,
/// arranged, at eye level. Nobody builds a display case for a status."*
///
/// `groups` is already the first N in the person's order; the "See all"
/// count is what sits behind it.
struct SystemsCase: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let groups: [HomeSystems.Group]
    let total: Int
    var onOpen: (String) -> Void
    var onSeeAll: () -> Void
    var onArrange: (() -> Void)?
    /// The same two choices every other shelf offers on a long-press. Tim,
    /// 09-08: *"it should prompt to let me arrange library to arrange home and
    /// to hide from home, just like the others."*
    var onArrangeHome: (() -> Void)?
    var onHide: (() -> Void)?

    /// Three across on a phone; on an iPad or a Mac the six fit in one row,
    /// which is how a shelf of hardware sits when there is room for it —
    /// three huge tiles two deep was a phone layout stretched, not a case.
    private var wide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    private var columns: [GridItem] {
        // At accessibility sizes three tiles across cannot hold a name; two
        // can, and the case still reads as a case.
        let count = typeSize.isAccessibilitySize ? (wide ? 3 : 2)
            : wide ? min(max(groups.count, 3), 6) : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: "Systems",
                        count: total,
                        systemImage: "arcade.stick.console.fill",
                        tint: LSTheme.accent,
                        onSeeAll: total > groups.count ? onSeeAll : nil)
                .contextMenu {
                    if let onArrange {
                        Button { onArrange() } label: {
                            Label("Arrange Systems…", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    if let onArrangeHome {
                        Button { onArrangeHome() } label: {
                            Label("Arrange Home…", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    if let onHide {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { onHide() }
                        } label: { Label("Hide from Home", systemImage: "eye.slash") }
                    }
                }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(groups, id: \.platform) { g in
                    SystemTile(group: g, onOpen: onOpen)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// One console in the case: its art, its name, what you have on it.
///
/// Extracted so the case and the full grid behind "See all" cannot drift —
/// the grid IS the case with every console in it, and a tile that looked
/// different in the two places would say they were different things.
struct SystemTile: View {
    let group: HomeSystems.Group
    var onOpen: (String) -> Void

    var body: some View {
        BouncyTap {
            onOpen(group.platform)
        } label: {
            VStack(spacing: 6) {
                PlatformIconView(platform: group.platform, size: 58)
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                Text(PlatformShort.name(group.platform))
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(Format.gameCount(group.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LSTheme.hairline))
        }
        .accessibilityLabel("\(PlatformShort.name(group.platform)), \(Format.gameCount(group.count))")
    }
}

/// Where "See all" on the systems header goes.
struct SystemsRoute: Hashable {}

/// **Every console you own, as the case rather than as a tab switch.**
///
/// "See all" used to change tabs — it left Home, landed in Library, and
/// showed the games rather than the consoles. Tim, 2026-09-08: *"it should
/// open a screen that's just a grid of all the consoles. Then tapping a
/// console would show your full library of games for that console."* So the
/// case keeps its six and this holds the rest, in the same order, with the
/// same tiles; a tap goes on to that console's games.
struct AllSystemsView: View {
    var onOpen: (String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil }) private var consoles: [Console]
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    @State private var adding = false

    /// The person's own order, and the same folding Home uses — so a console
    /// stored under two spellings is one tile here too. Consoles you own with
    /// nothing logged on them stand here as well: that is the whole point of
    /// the record, and a display case does not only hold the machines you
    /// happen to have games for.
    private var groups: [HomeSystems.Group] {
        HomeSystems.ordered(raw: themeSettings.first?.homeSystemsRaw,
                            available: HomeSystems.folded(games.filter { $0.status != .wishlist },
                                                          consoles: consoles.map(\.platform)))
    }

    private var wide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? (wide ? 3 : 2) : (wide ? 6 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(groups, id: \.platform) { g in
                    SystemTile(group: g, onOpen: onOpen)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle("Systems")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: {
                    Label("Add a console", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) { AddConsoleSheet().lsSheet() }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No consoles yet",
                                       systemImage: "arcade.stick.console.fill",
                                       description: Text("Add a game on a console, or add the console itself."))
            }
        }
    }
}

/// Whether a collection sits on Home, and putting it there.
///
/// The layout string is the only record of what Home shows, so both menus
/// that offer it — the shelf card's press-and-hold and the collection page's
/// ⋯ — read and write it through here rather than each parsing the grammar.
@MainActor
enum HomeShelf {
    static func isOnHome(_ collection: GameCollection, in context: ModelContext) -> Bool {
        let raw = ThemePalette.fetchOrCreate(in: context).homeLayoutRaw
        return HomeLayout.resolve(raw: raw).pinnedCollections.contains(collection.id)
    }

    static func setOnHome(_ collection: GameCollection, _ on: Bool, in context: ModelContext) {
        let settings = ThemePalette.fetchOrCreate(in: context)
        var layout = HomeLayout.resolve(raw: settings.homeLayoutRaw)
        if on { layout.pin(collection: collection.id) } else { layout.unpin(collection: collection.id) }
        settings.homeLayoutRaw = layout.raw
        settings.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
    }
}

/// The case before there is anything in it.
///
/// A new library's Home leads with the question rather than with an empty
/// shelf of games: *which consoles are yours?* Tapping goes to Add Game,
/// because in this build a console appears when a game does; the "who are
/// you as a gamer" first run (build 39) answers it without a game.
struct EmptySystemsCase: View {
    var onAdd: () -> Void
    /// **The question can be answered directly now.** This asked "which
    /// consoles are yours?" and then went to Add Game — the honest compromise
    /// while a console could only exist by way of a game on it. Build 39 makes
    /// a console a record you own, so the screen that asks the question offers
    /// the answer, and a game is the other way in rather than the only one.
    var onAddConsole: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: "Systems", count: nil,
                        systemImage: "arcade.stick.console.fill",
                        tint: LSTheme.accent)
            HStack(spacing: 10) {
                ForEach(["SNES?", "Switch?", "＋"], id: \.self) { word in
                    Button(action: onAddConsole ?? onAdd) {
                        Text(word)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LSTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 74)
                            .background(LSTheme.cardFill.opacity(0.6), in: .rect(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(LSTheme.accent.opacity(0.45),
                                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Which consoles are yours? Add one here.")
            .accessibilityAddTraits(.isButton)
            Text(onAddConsole == nil
                 ? "Which consoles are yours? Add a game on one and it sits here, in your order."
                 : "Which consoles are yours? Add one, or add a game on it — either way it sits here, in your order.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
}

// MARK: - A pinned collection

/// One collection as its own shelf: its covers in a row under its name.
///
/// "Six That Made Me" on Home says more than a composite tile in a shelf of
/// tiles — the prompt names are the self-portrait. A smart collection draws
/// the same way with its rule's members.
struct PinnedCollectionShelf: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let collection: GameCollection
    let members: [Game]
    var onOpen: (Game) -> Void
    var onOpenCollection: () -> Void
    var onUnpin: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: collection.name,
                        count: members.count,
                        systemImage: collection.isSmart ? "sparkles.rectangle.stack" : "rectangle.3.group.fill",
                        tint: LSTheme.accent,
                        onSeeAll: onOpenCollection)
                .contextMenu {
                    Button { onOpenCollection() } label: {
                        Label("Open Collection", systemImage: "rectangle.3.group")
                    }
                    if let onUnpin {
                        Button { onUnpin() } label: {
                            Label("Remove from Home", systemImage: "pin.slash")
                        }
                    }
                }

            if members.isEmpty {
                Text(collection.isSmart
                     ? "Nothing matches this rule yet."
                     : "Nothing in it yet. Open it to add games.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(members) { game in
                            BouncyTap {
                                onOpen(game)
                            } label: {
                                CoverCard(game: game)
                            }
                            .gameContextMenu(game)
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.86))
                                    .opacity(phase.isIdentity ? 1 : 0.6)
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
