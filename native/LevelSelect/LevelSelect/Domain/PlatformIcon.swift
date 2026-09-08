import Foundation

/// Which console artwork a platform string maps to.
///
/// Lives in Domain, not UI, despite naming image assets: it is pure
/// `String -> String?` platform knowledge with no SwiftUI in it, and
/// `Repository` needs it to merge platform lists — Repository is in the Watch
/// target, which compiles no UI at all. It sat in `LibraryView.swift` until
/// 2026-08-31, when refresh started merging platforms and the watch build
/// broke on the reference.
enum PlatformIcon {
    static func assetName(_ platform: String) -> String? {
        let p = platform.lowercased()
        if p.contains("switch 2")                              { return "platform-switch2" }
        if p.contains("switch")                                { return "platform-switch" }
        // **Japan's machines are their own machines**, and they have to be
        // tested before the Western names that contain them. "Super Famicom"
        // used to resolve to the SNES's art — a fair stand-in while there was
        // no Super Famicom render, and wrong now that there is: the SFC is
        // rounded and grey where the SNES is boxy and angular. "Famicom Disk
        // System" contains "famicom", and "Nintendo 64DD" contains
        // "nintendo 64", so both go above what they would otherwise match.
        if p.contains("famicom disk") || p.contains("family computer disk")
                                                               { return "platform-famicom-disk" }
        if p.contains("super famicom")                         { return "platform-superfamicom" }
        if p.contains("famicom") || p.contains("family computer")
                                                               { return "platform-famicom" }
        if p.contains("super nintendo") || p == "snes"         { return "platform-snes" }
        if p.contains("64dd")                                  { return "platform-64dd" }
        if p.contains("nintendo 64") || p == "n64"             { return "platform-n64" }
        if p == "nes" || p.contains("nintendo entertainment")  { return "platform-nes" }
        if p.contains("virtual boy")                           { return "platform-virtualboy" }
        if p.contains("gamecube")                              { return "platform-gamecube" }
        // The 32X is a Genesis wearing a mushroom, so its art IS a Genesis
        // with the 32X seated in it — and it has to be tested first or the
        // add-on would resolve to the console underneath.
        if p.contains("32x")                                   { return "platform-32x" }
        if p.contains("genesis") || p.contains("mega drive")   { return "platform-genesis" }
        if p.contains("dreamcast")                             { return "platform-dreamcast" }
        if p.contains("saturn")                                { return "platform-saturn" }
        if p.contains("master system") || p.contains("mark iii")
                                                               { return "platform-mastersystem" }
        if p.contains("game gear")                             { return "platform-gamegear" }
        // NEC's, under the name the app already folds it to. "PC Engine"
        // contains "pc", and the bare PC test further down is an exact match
        // rather than a substring, so this sits here for clarity rather than
        // out of necessity.
        if p.contains("turbografx") || p.contains("pc engine") { return "platform-turbografx16" }
        // Order matters: more specific strings first, since these are
        // substring matches ("xbox series" before "xbox", "ps5" before "ps").
        // This block used to violate its own rule — bare "xbox" sat above
        // "xbox series", so every Series X|S got the 2001 original's icon and
        // the platform-xbox-series art was unreachable.
        if p.contains("xbox 360")                              { return "platform-xbox360" }
        if p.contains("xbox series")                           { return "platform-xbox-series" }
        // The 2013 box. It borrowed the 2001 original's picture until Codex
        // drew it one, 2026-09-08 — and because sorting reads a console's year
        // off its ART, borrowing a picture meant borrowing 2001 and landing
        // ahead of the Xbox 360. Its own art, its own year, no override.
        if p.contains("xbox one")                              { return "platform-xbox-one" }
        if p.contains("xbox")                                  { return "platform-xbox" }
        // The slug stays `recalbox` — renaming an imageset renames it in the
        // year and maker tables and in every test that holds those together,
        // for a string nobody sees. The NAME is what changed; see
        // `PlatformKey.canonical`.
        if p.contains("recalbox") || p.contains("raspberry")
            || p.contains("retropie") || p.contains("batocera")
                                                               { return "platform-recalbox" }
        if p.contains("steam deck")                            { return "platform-steamdeck" }
        // Valve's living-room box. No conflict with the bare `steam` test
        // further down — that one is an exact match, not a substring.
        if p.contains("steam machine")                         { return "platform-steammachine" }
        if p.contains("playstation 5") || p == "ps5"           { return "platform-ps5" }
        if p.contains("playstation 4") || p == "ps4"           { return "platform-ps4" }
        if p.contains("playstation 3") || p == "ps3"           { return "platform-ps3" }
        if p.contains("playstation 2") || p == "ps2"           { return "platform-ps2" }
        if p == "playstation" || p.contains("playstation 1")
            || p == "ps1" || p == "psx"                        { return "platform-ps1" }
        // "PlayStation Vita" contains "playstation", so it has to be tested
        // before the bare check above would ever see it — it is above by
        // virtue of `vita` being the more specific string.
        if p.contains("playstation portable") || p == "psp"    { return "platform-psp" }
        if p.contains("vita")                                  { return "platform-vita" }
        if p.contains("3ds")                                   { return "platform-3ds" }
        // AFTER the 3DS, which contains "ds" — and matched by the full
        // "nintendo ds" or an exact short name, never a bare substring.
        if p.contains("nintendo ds") || p == "ds" || p == "dsi" { return "platform-ds" }
        if p.contains("wii u")                                 { return "platform-wiiu" }
        if p.contains("wii")                                   { return "platform-wii" }
        // Linux is here rather than on a penguin of its own: `PlatformKey`
        // folds it into PC, so the art has to follow the name or a folded
        // console would draw a picture no other PC draws.
        if p.contains("microsoft windows") || p == "pc" || p == "linux"
            || p == "windows" || p == "steam"                  { return "platform-pc" }
        // Game Boy family: the longer names contain "game boy", so they must
        // be tested first or every handheld collapses to the 1989 DMG.
        if p.contains("game boy advance") || p == "gba"        { return "platform-gba" }
        if p.contains("game boy color") || p == "gbc"          { return "platform-gbc" }
        if p.contains("game boy")                              { return "platform-gameboy" }
        if p == "ios" || p.contains("iphone")                  { return "platform-iphone" }
        if p.contains("ipad")                                  { return "platform-ipad" }
        if p == "android"                                      { return "platform-android" }
        if p == "mac" || p.contains("macintosh") || p.contains("macos") { return "platform-mac" }
        return nil
    }
}

extension PlatformIcon {
    /// Two spellings of one console collapsed to a single key, so "Switch" and
    /// "Nintendo Switch" are not treated as two systems.
    ///
    /// The console's artwork IS the identity: anything sharing an icon is the
    /// same box. Platforms with no icon fall back to their own lowercased
    /// name, which keeps unknown platforms distinct from each other.
    static func consoleKey(_ platform: String) -> String {
        assetName(platform) ?? platform.lowercased()
    }
}


import SwiftUI

/// A console icon sized for a MENU row.
///
/// The imagesets are 1024×1024. A bare `Image(asset)` in a `Label`'s icon slot
/// renders at native size, and while iOS quietly constrains menu images,
/// **macOS does not** — the System filter opened as a full-screen wall of
/// giant consoles, one per row, on 2026-08-31.
///
/// SwiftUI's sizing modifiers do not fix it either: AppKit draws a menu item's
/// image from an `NSImage` and ignores `.resizable().frame(…)` entirely, which
/// is why the obvious fix changed nothing. The image itself has to BE small,
/// so on macOS this redraws it at 16pt before handing it over. On iOS the
/// ordinary modifiers work and are used.
///
/// Use this anywhere a platform icon goes into a `Menu` or `Picker` row.
struct PlatformMenuIcon: View {
    let platform: String
    /// Matches the size AppKit gives an SF Symbol in a menu row.
    var size: CGFloat = 16

    var body: some View {
        if let asset = PlatformIcon.assetName(platform) {
            #if os(macOS)
            if let image = Self.menuSized(asset, side: size) {
                Image(nsImage: image)
            } else {
                Image(systemName: "gamecontroller")
            }
            #else
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            #endif
        } else {
            Image(systemName: "gamecontroller")
        }
    }

    #if os(macOS)
    /// Redrawn at menu size, because AppKit uses the NSImage's own dimensions.
    private static func menuSized(_ asset: String, side: CGFloat) -> NSImage? {
        guard let source = NSImage(named: asset) else { return nil }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
    #endif
}

/// **When each platform first went on sale in North America.**
///
/// For sorting your consoles into the order they arrived — Tim: *"being able
/// to auto sort by general console release (initial North American release for
/// now, not variations) could still be a decent option for quick ordering."*
///
/// North American release, and the ORIGINAL model only. No Mini, no OLED, no
/// Slim, no Pro, and no Japanese launch — a Genesis is 1989 here because that
/// is when it reached the shelves this app's users bought from, even though
/// the Mega Drive was 1988 at home.
///
/// Computers and phones have no single launch the way a console does, so they
/// take their platform's own first release: the IBM PC, the Macintosh, the
/// first iPhone. That is a judgement rather than a fact, and it is recorded
/// here so the next person does not have to re-derive it.
///
/// This is deliberately NOT `PlatformShort.rank`, which is a taste heuristic
/// for deciding which platform LABELS a game and ranks emulators last. Two
/// different questions; two different tables.
/// Who made it. Keyed by the icon slug, the way `PlatformEra` is, so a
/// platform can never have art without a maker — `PlatformEraTests` holds the
/// lists together.
///
/// **This exists so a list of consoles can be ordered by something other than
/// an opinion.** Any hand-written order is a claim about what matters most,
/// and the app's was a claim about its author: newest Nintendo first, because
/// that is what he plays. Tim, 2026-09-08: *"I think the list when adding
/// consoles this way should be sorted alphabetically by company, then by
/// release date. That way it's not opinionated in any way… this list starts
/// with switch 2."*
///
/// The entries that had no maker get their own name rather than a bucket at
/// the end, because "everything else, last" is another opinion. A PC is a PC.
enum PlatformMaker {
    static func of(_ platform: String) -> String? {
        guard let asset = PlatformIcon.assetName(platform) else { return nil }
        return makers[String(asset.dropFirst("platform-".count))]
    }

    static let makers: [String: String] = [
        "nes": "Nintendo", "snes": "Nintendo", "n64": "Nintendo", "gamecube": "Nintendo",
        "wii": "Nintendo", "wiiu": "Nintendo", "switch": "Nintendo", "switch2": "Nintendo",
        "gameboy": "Nintendo", "gbc": "Nintendo", "gba": "Nintendo", "3ds": "Nintendo",
        "ds": "Nintendo", "famicom": "Nintendo", "superfamicom": "Nintendo",
        "famicom-disk": "Nintendo", "virtualboy": "Nintendo", "64dd": "Nintendo",
        "ps1": "Sony", "ps2": "Sony", "ps3": "Sony", "ps4": "Sony", "ps5": "Sony",
        "vita": "Sony", "psp": "Sony",
        "xbox": "Microsoft", "xbox360": "Microsoft", "xbox-one": "Microsoft",
        "xbox-series": "Microsoft",
        "genesis": "Sega", "32x": "Sega", "dreamcast": "Sega", "saturn": "Sega",
        "mastersystem": "Sega", "gamegear": "Sega",
        "turbografx16": "NEC",
        "steamdeck": "Valve", "steammachine": "Valve",
        // **Where the maker is not the point, the kind is.** By company alone
        // this list opened with Apple and Google — two names that make phones
        // — above every console anyone came here for. Tim: *"It also feels
        // weird that Apple and Google are both first. Maybe we combine Apple
        // and Google phones to Mobile, windows/linux/mac/raspberry pi to
        // computers."* A heading is there to help someone find their console,
        // and "Computers" finds a Mac faster than "Apple" does.
        "pc": "Computers", "mac": "Computers", "recalbox": "Computers",
        "iphone": "Mobile", "ipad": "Mobile", "android": "Mobile",
    ]
}

enum PlatformEra {
    /// A console's year, read off its art.
    ///
    /// That indirection is deliberate — it is what stops art and years from
    /// drifting apart — but it means a console with no render of its own
    /// borrows whichever year came with the picture it borrowed. That happened
    /// exactly once, to the Xbox One, and a `sharedArtYears` override carried
    /// it from 09-08 until the render arrived later the same day. Every
    /// console now has its own art, so the override is gone rather than
    /// sitting empty; the comment is the record that it was needed.
    static func releaseYear(_ platform: String) -> Int? {
        guard let asset = PlatformIcon.assetName(platform) else { return nil }
        return years[String(asset.dropFirst("platform-".count))]
    }


    /// Keyed by the icon slug, so a platform can never have art without a year
    /// or a year without art — `PlatformEraTests` holds the two lists together.
    static let years: [String: Int] = [
        // Nintendo
        "nes": 1985, "snes": 1991, "n64": 1996, "gamecube": 2001,
        "wii": 2006, "wiiu": 2012, "switch": 2017, "switch2": 2025,
        "gameboy": 1989, "gbc": 1998, "gba": 2001, "3ds": 2011,
        // Sony
        "ps1": 1995, "ps2": 2000, "ps3": 2006, "ps4": 2013, "ps5": 2020,
        "vita": 2012,
        // Microsoft
        "xbox": 2001, "xbox360": 2005, "xbox-one": 2013, "xbox-series": 2020,
        "famicom": 1983, "superfamicom": 1990, "famicom-disk": 1986,
        "64dd": 1999, "virtualboy": 1995, "ds": 2004,
        // Sony
        "psp": 2005,
        // Sega. North American dates, the same rule the rest of the table
        // follows — Genesis is 1989 rather than the 1988 Mega Drive, so the
        // Dreamcast is 1999 rather than the 1998 Japanese launch, and the
        // Saturn is its 1995 US release rather than 1994.
        "genesis": 1989, "32x": 1994, "dreamcast": 1999, "saturn": 1995,
        "mastersystem": 1986, "gamegear": 1991,
        // NEC, by the American name and date: the PC Engine was 1987 in
        // Japan, the TurboGrafx-16 was 1989 here.
        "turbografx16": 1989,
        // Valve. `steammachine` is the 2026 console, which shipped in June —
        // NOT the 2015 Steam Machine, a line of third-party PCs that shared
        // the name and died quietly. Two products, one name; the art in
        // `platform-steammachine` is the new one, so this is the new one.
        "steamdeck": 2022, "steammachine": 2026,
        // Computers — the platform's own first release, not a console launch.
        "pc": 1981, "mac": 1984,
        // Phones and tablets, same rule.
        "iphone": 2007, "ipad": 2010, "android": 2008,
        // Emulation frontends take their project's first public release.
        "recalbox": 2015,
    ]
}
