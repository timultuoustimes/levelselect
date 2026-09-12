import SwiftUI

enum Format {
    /// Compact human duration, e.g. "1h 12m", "12m 5s", "42s".
    /// Rounded hours, for figures that are approximations to begin with —
    /// "~14h" rather than "14h 24m", which would imply a precision that an
    /// average of a dozen strangers' playthroughs does not have.
    static func hours(_ t: TimeInterval) -> String {
        let h = t / 3600
        return h < 10 ? String(format: "%.1fh", h) : "\(Int(h.rounded()))h"
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// The same duration, said out loud.
    ///
    /// `duration` is written for a label, and VoiceOver reads its units as
    /// units: a 50-minute session was announced as **"50 meters 0 S"**. Found
    /// by Tim testing the Journal calendar with VoiceOver on 2026-09-04.
    ///
    /// Also drops a zero component — "50m 0s" has a trailing "0s" that is
    /// noise on screen and nonsense spoken.
    static func spokenDuration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append("\(sec) second\(sec == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// Video timestamp, e.g. "4:02" or "1:12:41".
    /// **A game's title as a short mark**, for a cover with no art.
    ///
    /// Tim's rule: the initials of the words that carry meaning, the colon
    /// kept as a separator, numerals and roman numerals left whole.
    ///
    ///     The Legend of Heroes: Trails of Cold Steel  ->  LH:TCS
    ///     Hollow Knight                               ->  HK
    ///     Vampire Survivors                           ->  VS
    ///     Cat Quest III                               ->  CQIII
    ///     Sonic the Hedgehog 2                        ->  SH2
    ///
    /// Multi-letter rather than one initial, because one initial cannot tell
    /// two games apart and a real library is full of pairs — Hades and Hollow
    /// Knight are both H. The colon survives because a subtitle is the thing
    /// that distinguishes entries in a series from each other, which is
    /// exactly when you need the mark to be specific.
    static func abbreviation(_ title: String) -> String {
        // Only a LEADING article is dropped. "The Legend of Heroes" is LH, but
        // "Journey to the Savage Planet" keeps its shape from the other words
        // rather than losing its first letter.
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["The ", "A ", "An "] where t.lowercased().hasPrefix(article.lowercased()) {
            t = String(t.dropFirst(article.count))
            break
        }
        let skipped: Set<String> = ["the", "of", "a", "an", "and", "to", "in", "for", "or"]
        // **Capped, because a title can be arbitrarily long and a mark cannot.**
        // Without this, "The Legend of Heroes: Trails of Cold Steel IV..." on
        // Home came out as LH:TCSIVESFEDDSC — sixteen characters, which at the
        // width of a cover card sets at six points and is a smear rather than a
        // mark. Three tokens a segment and two segments lands Tim's own example
        // exactly (LH:TCS) and truncates the runaway case to the same thing.
        let tokensPerSegment = 3
        let segments = 2
        let parts = t.split(separator: ":").prefix(segments).map { segment -> String in
            segment
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .filter { !skipped.contains($0.lowercased()) }
                .prefix(tokensPerSegment)
                .map { word -> String in
                    // "III" and "2" are the whole point of the title they are
                    // in — an initial would turn Cat Quest III into CQI and
                    // collide it with the first game.
                    let isNumeral = word.allSatisfy(\.isNumber)
                    let isRoman = word.count > 1 && word.allSatisfy { "IVXLCivxlc".contains($0) }
                    return isNumeral || isRoman ? word.uppercased() : String(word.prefix(1)).uppercased()
                }
                .joined()
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ":")
    }

    /// "1 game" / "12 games". One place, because the collection card and the
    /// collection page were saying the same thing in two spellings.
    static func gameCount(_ n: Int) -> String {
        "\(n) game\(n == 1 ? "" : "s")"
    }

    static func timestamp(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    /// Stopwatch clock, e.g. "01:02:03".
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

extension GameStatus {
    /// The app has exactly one public vocabulary for status, and this is it.
    /// It used to be `rawValue.capitalized`, which meant one menu said
    /// "Playing / Queued / Ongoing" while every shelf, filter and setting
    /// beside it said "Now Playing / Up Next / Always Around". Status is a
    /// central idea in this app; it does not get to change names depending on
    /// which surface was written first.
    @MainActor
    var label: String { sectionTitle }

    /// Themed status color (user override → default palette).
    @MainActor
    var color: Color {
        ThemePalette.color(for: self)
    }

    var systemImage: String {
        switch self {
        case .playing:   "play.circle.fill"
        case .paused:    "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .queued:    "text.append"
        case .backlog:   "tray.full"
        // The heart moved here when the Wishlist tab became a bag. A heart
        // was always a strange glyph for "want" — it says love, which is what
        // this status is actually about — and holding both meanings at once
        // was why neither could use it well.
        case .oldFavorite: "heart.fill"
        case .shelved:   "archivebox"
        case .abandoned: "xmark.circle"
        // Matches the tab. They disagreed until now, which is the sort of
        // thing nobody notices and everybody feels.
        case .wishlist:  "bag.fill"
        case .ongoing:   "infinity"
        }
    }

    /// Display order for grouped library sections.
    ///
    /// `ongoing` sits straight after `playing`: a game you keep coming back to
    /// is closer to what you're playing than to a backlog, and burying it
    /// below the finished pile would defeat the point of having the status.
    static var displayOrder: [GameStatus] {
        // Old Favorite sits with the past-tense statuses rather than the
        // queue: it is where a game ends up, not where it waits.
        [.playing, .ongoing, .paused, .queued, .backlog, .wishlist,
         .completed, .oldFavorite, .shelved, .abandoned]
    }

    /// The statuses Home carries: what is live and what is next.
    ///
    /// Home and Library had drifted into the same screen with different
    /// spacing — both listed every status, so the two tabs answered one
    /// question twice. Tim's split: **Home is you right now, Library is the
    /// collection.** A backlog, a finished pile and an abandoned shelf are
    /// facts about a collection; they are not what you opened the app to do.
    ///
    /// Wishlist is absent for a different reason — it has its own tab, and it
    /// is the one status that isn't part of the library at all.
    static var homeOrder: [GameStatus] {
        [.playing, .ongoing, .paused, .queued]
    }

    /// The built-in word. `sectionTitle` prefers the user's, when they have
    /// one — see `ThemePalette.statusName(for:)`.
    var defaultTitle: String {
        switch self {
        case .playing:   "Now Playing"
        case .paused:    "Paused"
        case .queued:    "Up Next"
        case .backlog:   "Backlog"
        case .completed: "Completed"
        case .oldFavorite: "Old Favorite"
        case .shelved:   "Shelved"
        case .abandoned: "Abandoned"
        case .wishlist:  "Wishlist"
        // Not "Ongoing": the heading is what these games ARE to someone —
        // Minecraft, a city builder, a live-service game they drift back to
        // for a fortnight twice a year. There is no finish line to be short
        // of, so none of the other statuses fit without implying one.
        case .ongoing:   "Always Around"
        }
    }

    /// What this status is actually called here.
    ///
    /// Routed through the palette exactly like `color`, so renaming reaches
    /// every shelf heading, filter chip and picker without 22 call sites
    /// having to know it exists.
    @MainActor
    var sectionTitle: String { ThemePalette.statusName(for: self) }
}

/// Tim's platform preference for defaulting new adds: Nintendo eShop first
/// (Switch 2, then Switch), then Steam/PC, then Mac; everything else after,
/// in IGDB's order.
enum PlatformPreference {
    /// Names that describe HOW a game is run, not what it ran on.
    ///
    /// These rank last so the original hardware leads: a MAME copy of Metal
    /// Slug is a Neo Geo game you happen to run in MAME, and the shelf should
    /// say Neo Geo. The list is deliberately generous — a name here costs one
    /// wrong sort at worst, while a name missing from it puts "Dolphin" at the
    /// head of a shelf where "GameCube" belongs.
    ///
    /// Two kinds, both treated the same way:
    ///
    /// **Frontends** — one program, many systems: RetroArch, Batocera,
    /// Recalbox, EmuDeck, EmulationStation/ES-DE, RetroBat, LaunchBox, Pegasus,
    /// Playnite.
    ///
    /// **System emulators** — one program, one machine: Dolphin (GameCube and
    /// Wii), PCSX2 (PS2), RPCS3 (PS3), DuckStation (PS1), PPSSPP (PSP), Cemu
    /// (Wii U), Ryujinx (Switch), Citra (3DS), melonDS, mGBA, Delta (iOS),
    /// Flycast, Redream, Xemu, xenia, Mesen, Snes9x, Nestopia, Yuzu.
    ///
    /// Yuzu and Citra were shut down in 2024 and Ryujinx left GitHub after
    /// legal pressure; their names stay because libraries recorded before that
    /// still carry them, and this list exists to sort names people have
    /// already typed rather than to recommend software.
    static func isEmulator(_ p: String) -> Bool {
        let names = [
            "retroarch", "batocera", "recalbox", "emudeck", "emulationstation",
            "es-de", "retrobat", "launchbox", "pegasus", "playnite",
            "mame", "dolphin", "pcsx2", "nethersx2", "armsx2", "rpcs3",
            "duckstation", "ppsspp", "cemu", "ryujinx", "yuzu", "citra",
            "melonds", "mgba", "delta", "flycast", "redream", "xemu",
            "xenia", "mesen", "snes9x", "nestopia", "vice", "fs-uae",
        ]
        return names.contains { p.contains($0) }
    }


    static func rank(_ platform: String) -> Int {
        let p = platform.lowercased()
        if p.contains("switch 2") { return 0 }
        if p.contains("switch") { return 1 }
        if p.contains("windows") || p == "pc" || p.contains("steam") { return 2 }
        if p.contains("mac") { return 3 }
        // Emulation frontends rank LAST so the original hardware leads (e.g.
        // Sonic 2 on Genesis + Recalbox → Genesis).
        // A storefront ranks below the hardware it runs on: a game held on
        // both PC and itch.io is a PC game you happened to buy on itch, and
        // the shelf should say PC. When itch is the ONLY platform — the usual
        // case for these — it leads by default.
        if p.contains("itch") { return 150 }
        if isEmulator(p) { return 200 }
        return 100
    }

    /// The platform the user actually owns or played on — position zero.
    ///
    /// `addGame(from:platform:)` stores the platform picked on the confirm
    /// screen at the FRONT of the list, so position zero is a record of an
    /// answer the user gave, not a guess. `sorted()` is a guess: a fixed taste
    /// ranking that put PC above Xbox 360 and so labeled a 360 copy of Skyrim
    /// "PC" on the game page, in the library row, and in the platform grouping.
    ///
    /// A record beats a heuristic, always. `sorted()` stays for the places
    /// where no choice has been made yet — ordering the picker itself, and
    /// search results for games that aren't in the library.
    static func owned(_ platforms: [String]) -> String? { platforms.first }

    /// Stable sort: preferred platforms first, original order preserved otherwise.
    static func sorted(_ platforms: [String]) -> [String] {
        platforms.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

/// Async cover art with a themed placeholder. Box-art aspect ratio.
struct CoverThumb: View {
    let urlString: String?
    /// The game's own resolved artwork, when the call site has a game.
    ///
    /// **Without this, a cover you chose yourself did not appear on any
    /// shelf.** `ArtworkPointer` stores a picked photo as
    /// `levelselect-image:<id>`, and `Game.displayCoverURLString` returns nil
    /// for that on purpose — it will not substitute the fetched cover for the
    /// one you actually picked. But this view only ever knew how to load a
    /// URL, so nil meant the placeholder: the game page showed your picture
    /// (it goes through `ArtworkView`) while Home, Library, the shelves, the
    /// running-timer strip and Continue Playing all showed a grey controller.
    ///
    /// That is the shape behind Fable 2.7 and 2.17, both filed as
    /// "placeholder instead of the game's cover, cause unknown". Their stated
    /// cause — that the shelf resolves artwork and the strip does not — was
    /// not it: every one of these sites was URL-only. The difference was
    /// whose cover it was.
    ///
    /// Optional because six call sites have no game in scope (the artwork
    /// picker, the profile backdrop, Recently Deleted) and are unchanged.
    var artwork: ResolvedArtwork? = nil
    /// The game's title, for the placeholder when there is no art. Nil at the
    /// six call sites with no game in scope — the artwork picker, the profile
    /// backdrop, recently deleted — which keep the old glyph.
    var name: String? = nil
    /// Colors the mark, the way every other status glyph in the app is
    /// colored. Nil falls back to secondary ink.
    var status: GameStatus? = nil
    /// Fill is right for box art, which is meant to be cropped to a shelf
    /// tile. It is wrong for a wordmark: a wide logo in a 2.2 tile gets its
    /// ends cut off, so the picker offered a row of "T FIGHT" and "ET FIGHTE"
    /// with no way to tell which logo you were choosing.
    var contentMode: ContentMode = .fill

    /// **Resolved artwork can be remote too, and that branch was missing.**
    ///
    /// `artwork` only ever answered the `.local` question; a `.remote` value
    /// fell through to `urlString`, which is right for every site that passes
    /// both and wrong for the one that passes artwork ALONE. `PlayerSummary`
    /// became `[ResolvedArtwork]` this morning and Home's header started
    /// handing over `.remote(url)` with a nil string — so the band that had
    /// just been taught about local covers stopped drawing remote ones, which
    /// is every cover most people have. Tim saw it the same afternoon.
    private var remoteURL: URL? {
        if case .remote(let url) = artwork { return url }
        return urlString.flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            // Local first: a picture the user chose beats one the app fetched,
            // which is the same precedence `displayCoverURLString` applies.
            if case .local(let data) = artwork, let image = PlatformImage(data: data) {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: contentMode)
                    case .empty: ProgressView()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .coverGloss(cornerRadius: 6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
    }

    /// **A missing cover says which game it is.**
    ///
    /// It used to be a gray field and one `gamecontroller.fill`, which is the
    /// same object for every game in the library — four unmatched games on a
    /// shelf read as four copies of one thing. Now it carries the title as a
    /// short mark in the app's own face, in the game's status color, with the
    /// hard step the wordmark and the profile name already wear.
    ///
    /// Fable's 5.7 proposed the full name in the status color. Two things
    /// sent it here instead. The name is already printed under the card on
    /// shelves and in rows — so drawing it inside repeats it exactly where the
    /// card is biggest — and at the 44pt calendar cell a name is not readable
    /// at any weight. An abbreviation survives every size this appears at,
    /// which runs from 44pt to 108pt.
    ///
    /// The step is not decoration. Pixel strokes are two pixels wide and a
    /// flat fill on a mid-tone card goes soft; the offset adds a second
    /// contrast edge, which is the whole reason the wordmark has one. Tim, on
    /// seeing it: *"Darker offset on the light background provides smaller
    /// text a bit more contrast which makes it a little easier to read."*
    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.quaternary)
                if let mark = name.map(Format.abbreviation), !mark.isEmpty {
                    // Sized to the card AND to the mark's length, because they
                    // pull in opposite directions: the face is monospaced at
                    // one em per character, so LH:TCS needs six times the width
                    // of H and has to give up type size to get it.
                    let side = min(geo.size.width, geo.size.height)
                    let type = min(side * 0.28, geo.size.width * 0.9 / CGFloat(mark.count))
                    let ink = status?.color ?? .secondary
                    Text(mark)
                        .font(LSTheme.pixel(type))
                        .fontDesign(nil)
                        .foregroundStyle(ink)
                        .shadow(color: LSTheme.hardStep(under: ink), radius: 0,
                                y: LSTheme.pixelStep(for: type))
                        .lineLimit(1)
                        // Shrink rather than truncate. The sizing above should
                        // make this unreachable, but a mark with an ellipsis in
                        // it would be worse than a small one.
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // The mark names the game the caller has already named. Two readings
        // of the same title is noise, and the six nameless call sites have
        // nothing to announce anyway.
        .accessibilityHidden(true)
    }
}
