import SwiftUI
import SwiftData

/// Canonical list of common platforms offered in the picker, so platforms are
/// SELECTED (no typos, no accidental duplicates). Existing library platforms
/// are merged in ahead of these.
enum PlatformCatalog {
    static let all = [
        "Switch 2", "Switch", "PC", "Mac", "Steam Deck", "Steam Machine",
        "PS5", "PS4", "PS3", "PS2", "PS1", "PSP", "PS Vita",
        "Xbox Series X", "Xbox One", "Xbox 360", "Xbox",
        "Wii U", "Wii", "GameCube", "N64", "SNES", "NES",
        "3DS", "DS", "GBA", "Game Boy Color", "Game Boy",
        "Genesis", "32X", "Saturn", "Dreamcast", "Master System", "Game Gear",
        "Atari 2600", "Atari 5200", "Atari 7800", "Atari Lynx", "Atari Jaguar",
        "Commodore 64", "Amiga", "Amiga CD32",
        "Neo Geo AES", "Neo Geo MVS", "Neo Geo Pocket Color",
        "Intellivision", "ColecoVision", "Vectrex", "ZX Spectrum", "MSX",
        "3DO", "WonderSwan Color", "Arcade",
        // Japan's own machines, which are not the Western ones renamed: the
        // Super Famicom is a different box from the SNES and now has its own
        // art. Build 39, when the consoles became records worth adding by
        // hand rather than only names a game arrived under.
        "Famicom", "Famicom Disk System", "Super Famicom", "Virtual Boy",
        "TurboGrafx-16",
        "Raspberry Pi", "iOS", "Android",
        // A storefront, not a machine — and the one platform whose games
        // routinely have no IGDB entry at all, which is exactly why it has to
        // be nameable by hand.
        "itch.io",
    ]

    /// Two spellings of the same console collapse to one key (so "Switch" and
    /// "Nintendo Switch" aren't offered twice). See `PlatformIcon.consoleKey`
    /// — one definition, shared with `Repository.mergePlatforms`.
    static func normalize(_ platform: String) -> String {
        PlatformIcon.consoleKey(platform)
    }
}

/// Platforms editor that PICKS from known platforms (library + catalog) instead
/// of free text — prevents typos and duplicate platforms. Chips show the
/// console icon; "Other…" still allows a genuinely new platform.
struct PlatformEditor: View {
    @Binding var platforms: [String]
    /// The platforms you own it on. Schema V3 — see `Game.ownedPlatforms`.
    /// A set, because owning a game on two consoles is ordinary.
    @Binding var owned: [String]
    /// True when this game's list comes from IGDB and can be trusted to say
    /// what it actually shipped on. The catalog then sits behind a submenu
    /// rather than at the top level — Cities: Skylines offering Game Boy, NES
    /// and Genesis as one-tap options is noise, and it buries the handful of
    /// consoles the game exists on. A hand-added game has no such list, so
    /// there the catalog IS the answer and stays where it was.
    var listIsAuthoritative = false
    /// **A wishlist game claims nothing.** Passed in rather than read from a
    /// game, because this editor edits two bindings and has never held one.
    /// See `Game.badgeableOwnedPlatforms` for why the status decides.
    var isWishlist = false

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var allGames: [Game]
    /// The consoles you hold a record for. They lead the menu, because the
    /// console you own is overwhelmingly the one you are about to pick.
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil })
    private var consoles: [Console]

    @State private var addingCustom = false
    @State private var custom = ""
    @State private var browsing = false

    /// Mirrors `Game.ownedPlatformNames`: an empty set on a pre-V3 game means
    /// "never recorded", and position zero is what the app meant then.
    private var ownedNames: [String] {
        owned.isEmpty ? platforms.first.map { [$0] } ?? [] : owned
    }

    /// What the chips LIGHT UP, which the game page now matches — see
    /// `Game.badgeableOwnedPlatforms`. A wishlist game claims nothing.
    private var litNames: [String] {
        isWishlist ? [] : ownedNames
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Platforms").font(.caption).foregroundStyle(.secondary)

            if !platforms.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(PlatformShort.ownedFirst(platforms, owned: ownedNames), id: \.self) { platform in
                        chip(platform)
                    }
                }
            }

            Menu {
                // **Your consoles first, and one tap away.** Everything used
                // to sit behind "Another console…" in an order that was
                // library-then-catalog and read as no order at all. Tim,
                // 2026-09-08: *"Tapping twice to add a console to a game on a
                // game's page needs fixed. That list should sort by your
                // consoles at the top, others below that."*
                buttons(for: mine)
                if !mine.isEmpty && !others.isEmpty { Divider() }
                if listIsAuthoritative || !mine.isEmpty {
                    // **A sheet, because a menu cannot be searched.** Emulation
                    // and unlisted ports are real, so the rest of the
                    // catalogue is one step further away rather than gone —
                    // but it is now sixty-odd machines, which is a long scroll
                    // to find the one you meant. Tim, 2026-09-08: *"Maybe we
                    // could add a search to that menu? It's a lot of consoles,
                    // and I doubt most people will be manually adding much
                    // since they get filled when adding a game."*
                    Button { browsing = true } label: {
                        Label("Another console…", systemImage: "gamecontroller")
                    }
                } else {
                    buttons(for: others)
                }
                Divider()
                Button { addingCustom = true } label: {
                    Label("Other…", systemImage: "plus")
                }
            } label: {
                Label("Add platform", systemImage: "plus.circle")
                    .font(.caption)
            }
        }
        .sheet(isPresented: $browsing) {
            PlatformPickerSheet(mine: mine, others: others) { platform in
                add(platform)
            }
            .lsSheet()
        }
        .alert("New platform", isPresented: $addingCustom) {
            TextField("Platform name", text: $custom)
            Button("Add") {
                let value = custom.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { add(value) }
                custom = ""
            }
            Button("Cancel", role: .cancel) { custom = "" }
        }
    }

    /// Tap a chip to toggle whether you own the game on that console.
    ///
    /// It used to mean "move this to position zero", because position zero WAS
    /// the ownership record — so marking a second console silently unmarked
    /// the first, and owning a game on both was unrepresentable. Now it is a
    /// set, and the chips are checkboxes.
    private func chip(_ platform: String) -> some View {
        let isMine = litNames.contains(platform)
        return Button {
            toggleMine(platform)
        } label: {
        HStack(spacing: 5) {
            PlatformIconView(platform: platform, size: 15)
            Text(PlatformShort.name(platform)).font(.caption)
            if isMine {
                Text("MINE").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LSTheme.accent)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        // Accent means "mine"; not-mine is a plain surface, not a second
        // accent. Fixed blue made an unowned platform look like a differently
        // selected one, and stayed blue in a lime, orange or purple app —
        // the only unexplained theme bypass in the audit. Codex K5.
        .background(isMine ? AnyShapeStyle(LSTheme.accent.opacity(0.18))
                           : AnyShapeStyle(LSTheme.cardFill), in: .capsule)
        .overlay(Capsule().strokeBorder(
            isMine ? AnyShapeStyle(LSTheme.accent.opacity(0.55))
                   : AnyShapeStyle(LSTheme.hairline), lineWidth: 1))
        .foregroundStyle(.primary)
        .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // **The common action on the tap, the rare one behind the hold.**
        //
        // This was a 22-point remove Button nested inside a tap gesture on the
        // chip — two actions on one capsule, the inner one under the 44-point
        // minimum, and removing a console (which you almost never do) easier
        // to hit by accident than owning one. The repair moved BOTH actions
        // into the context menu, which fixed the collision and then went one
        // step too far: tapping a chip did nothing at all, so the everyday
        // action needed a long press and a sighted user had no affordance for
        // it. Codex called that a regression on 2026-09-07 and was right.
        //
        // Tim asked for the hold — *"press and hold a console > select 'make
        // mine'?"* — and it stays, because that is where Remove belongs. What
        // comes back is the tap, on the whole capsule, doing the thing the
        // chip is a checkbox for.
        .lsTapTargetTall()
        .contextMenu {
            Button {
                toggleMine(platform)
            } label: {
                Label(isMine ? "Not mine" : "Make mine",
                      systemImage: isMine ? "xmark.circle" : "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                platforms.removeAll { $0 == platform }
                // A console you no longer list cannot be one you own it on.
                owned.removeAll { $0 == platform }
            } label: {
                Label("Remove \(PlatformShort.name(platform))", systemImage: "trash")
            }
        }
        .accessibilityHint("Marks whether the game is yours here. Press and hold to remove it.")
        .accessibilityValue(isMine ? "Mine" : "Not marked as yours")
    }

    private func toggleMine(_ platform: String) {
        var next = ownedNames
        if let index = next.firstIndex(of: platform) {
            next.remove(at: index)
        } else {
            next.append(platform)
        }
        withAnimation(.snappy(duration: 0.28)) { owned = next }
    }

    /// **Adding a console by hand says it is yours.**
    ///
    /// The list a game arrives with is IGDB's — every machine it shipped on,
    /// most of which you do not own — so "mine" has to be a separate mark
    /// there. But nobody reaches into this menu to record a platform they
    /// have no copy on. Tim, 2026-09-08: *"I kind of think people would only
    /// be manually adding a console to a game because they have it there, so
    /// it should mark it as 'mine' when I add it."* Tapping the chip still
    /// unmarks it, so the guess costs one tap when it is wrong and saves one
    /// every other time.
    private func add(_ platform: String) {
        guard !platforms.contains(platform) else { return }
        platforms.append(platform)
        var next = ownedNames
        if !next.contains(platform) {
            next.append(platform)
            owned = next
        }
    }

    @ViewBuilder
    private func buttons(for list: [String]) -> some View {
        ForEach(list, id: \.self) { platform in
            Button {
                add(platform)
            } label: {
                Label {
                    Text(PlatformShort.name(platform))
                } icon: {
                    PlatformMenuIcon(platform: platform)
                }
            }
        }
    }

    /// The consoles you own, minus the ones already on this game.
    private var mine: [String] {
        let current = Set(platforms.map(PlatformCatalog.normalize))
        var seen = Set<String>()
        return consoles.map(\.platform)
            .filter { !current.contains(PlatformCatalog.normalize($0)) }
            .filter { seen.insert(PlatformCatalog.normalize($0)).inserted }
            .sorted { PlatformShort.name($0).localizedCaseInsensitiveCompare(
                          PlatformShort.name($1)) == .orderedAscending }
    }

    /// Everything else the app knows, alphabetically by the name you see.
    ///
    /// It was library-order then catalog-order before, which put the
    /// platforms IGDB happens to list on your games in front in a sequence
    /// nobody could read as a sequence.
    private var others: [String] {
        let already = Set(mine.map(PlatformCatalog.normalize))
        return available
            .filter { !already.contains(PlatformCatalog.normalize($0)) }
            .sorted { PlatformShort.name($0).localizedCaseInsensitiveCompare(
                          PlatformShort.name($1)) == .orderedAscending }
    }

    // MARK: Options

    private var libraryPlatforms: [String] {
        var seen = Set<String>(); var out: [String] = []
        for g in allGames {
            for p in g.platforms where seen.insert(p).inserted { out.append(p) }
        }
        return out.sorted { (PlatformPreference.rank($0), $0) < (PlatformPreference.rank($1), $1) }
    }

    /// Library platforms first (so you reuse existing names), then catalog
    /// entries for consoles you don't have yet — deduped by console.
    private var options: [String] {
        var keys = Set<String>(); var out: [String] = []
        for p in libraryPlatforms + PlatformCatalog.all {
            if keys.insert(PlatformCatalog.normalize(p)).inserted { out.append(p) }
        }
        return out
    }

    private var available: [String] {
        let current = Set(platforms.map(PlatformCatalog.normalize))
        return options.filter { !current.contains(PlatformCatalog.normalize($0)) }
    }
}

/// **The whole catalogue, searchable.** The rest of the consoles lived in a
/// submenu until 2026-09-08, when there were sixty of them and no way to jump
/// to one — Tim: *"It's a lot of consoles... The only platform I'll likely be
/// adding to games is Raspberry Pi, since IGDB doesn't list emulation as a
/// platform."* That is the case this exists for: a machine IGDB will never
/// name, reached by typing four letters instead of scrolling past Amstrad.
///
/// Yours stay at the top, here as well as in the menu that opens this.
struct PlatformPickerSheet: View {
    let mine: [String]
    let others: [String]
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private func matches(_ list: [String]) -> [String] {
        guard !search.isEmpty else { return list }
        return list.filter {
            PlatformShort.name($0).localizedCaseInsensitiveContains(search)
                || $0.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !matches(mine).isEmpty {
                    Section("Your consoles") {
                        ForEach(matches(mine), id: \.self, content: row)
                    }
                    .listRowBackground(LSTheme.cardFill)
                }
                if !matches(others).isEmpty {
                    Section(matches(mine).isEmpty ? "Consoles" : "Everything else") {
                        ForEach(matches(others), id: \.self, content: row)
                    }
                    .listRowBackground(LSTheme.cardFill)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LSTheme.liveSheetGround)
            .searchable(text: $search, prompt: "Search consoles")
            .navigationTitle("Add a platform")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if matches(mine).isEmpty && matches(others).isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private func row(_ platform: String) -> some View {
        Button {
            onPick(platform)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                PlatformIconView(platform: platform, size: 26)
                Text(PlatformShort.name(platform))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
