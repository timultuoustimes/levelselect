import SwiftUI
import SwiftData

/// Canonical list of common platforms offered in the picker, so platforms are
/// SELECTED (no typos, no accidental duplicates). Existing library platforms
/// are merged in ahead of these.
enum PlatformCatalog {
    static let all = [
        "Switch 2", "Switch", "PC", "Mac", "Steam Deck", "Steam Machine", "Linux",
        "PS5", "PS4", "PS3", "PS2", "PS1", "PSP", "PS Vita",
        "Xbox Series X", "Xbox One", "Xbox 360", "Xbox",
        "Wii U", "Wii", "GameCube", "N64", "SNES", "NES",
        "3DS", "DS", "GBA", "Game Boy Color", "Game Boy",
        "Genesis", "Saturn", "Dreamcast", "Recalbox", "iOS", "Android",
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

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var allGames: [Game]

    @State private var addingCustom = false
    @State private var custom = ""

    /// Mirrors `Game.ownedPlatformNames`: an empty set on a pre-V3 game means
    /// "never recorded", and position zero is what the app meant then.
    private var ownedNames: [String] {
        owned.isEmpty ? platforms.first.map { [$0] } ?? [] : owned
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
                if listIsAuthoritative {
                    // Emulation and unlisted ports are real, so this is a
                    // submenu rather than a removal — one step further away,
                    // not gone.
                    Menu {
                        catalogButtons
                    } label: {
                        Label("Another console…", systemImage: "gamecontroller")
                    }
                } else {
                    catalogButtons
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
        .alert("New platform", isPresented: $addingCustom) {
            TextField("Platform name", text: $custom)
            Button("Add") {
                let value = custom.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !platforms.contains(value) { platforms.append(value) }
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
        let isMine = ownedNames.contains(platform)
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

    @ViewBuilder
    private var catalogButtons: some View {
        ForEach(available, id: \.self) { platform in
            Button {
                platforms.append(platform)
            } label: {
                Label {
                    Text(PlatformShort.name(platform))
                } icon: {
                    PlatformMenuIcon(platform: platform)
                }
            }
        }
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
