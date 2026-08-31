import SwiftUI
import SwiftData

/// Canonical list of common platforms offered in the picker, so platforms are
/// SELECTED (no typos, no accidental duplicates). Existing library platforms
/// are merged in ahead of these.
enum PlatformCatalog {
    static let all = [
        "Switch 2", "Switch", "PC", "Mac", "Steam Deck",
        "PS5", "PS4", "PS3", "PS2", "PS1", "PSP", "PS Vita",
        "Xbox Series X", "Xbox One", "Xbox 360", "Xbox",
        "Wii U", "Wii", "GameCube", "N64", "SNES", "NES",
        "3DS", "DS", "GBA", "Game Boy Color", "Game Boy",
        "Genesis", "Saturn", "Dreamcast", "Recalbox", "iOS", "Android",
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
        return HStack(spacing: 5) {
            PlatformIconView(platform: platform, size: 15)
            Text(PlatformShort.name(platform)).font(.caption)
            if isMine {
                Text("MINE").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LSTheme.accent)
            }
            Button {
                platforms.removeAll { $0 == platform }
                // A console you no longer list cannot be one you own it on.
                owned.removeAll { $0 == platform }
            } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    // An 8pt glyph is a caption, not a target.
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(PlatformShort.name(platform))")
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background((isMine ? LSTheme.accent : .blue).opacity(0.18), in: .capsule)
        .overlay(Capsule().strokeBorder((isMine ? LSTheme.accent : .blue).opacity(isMine ? 0.55 : 0.35), lineWidth: 1))
        .foregroundStyle(.primary)
        .contentShape(.capsule)
        .onTapGesture {
            var next = ownedNames
            if let index = next.firstIndex(of: platform) {
                next.remove(at: index)
            } else {
                next.append(platform)
            }
            withAnimation(.snappy(duration: 0.28)) { owned = next }
        }
        .accessibilityHint(isMine
                           ? "Double tap to unmark as a platform you own"
                           : "Double tap to mark as a platform you own")
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
