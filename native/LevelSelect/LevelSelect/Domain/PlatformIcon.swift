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
        if p.contains("super nintendo") || p == "snes"
            || p.contains("super famicom")                     { return "platform-snes" }
        if p.contains("nintendo 64") || p == "n64"             { return "platform-n64" }
        if p == "nes" || p.contains("nintendo entertainment")  { return "platform-nes" }
        if p.contains("gamecube")                              { return "platform-gamecube" }
        if p.contains("genesis") || p.contains("mega drive")   { return "platform-genesis" }
        // Order matters: more specific strings first, since these are
        // substring matches ("xbox series" before "xbox", "ps5" before "ps").
        // This block used to violate its own rule — bare "xbox" sat above
        // "xbox series", so every Series X|S got the 2001 original's icon and
        // the platform-xbox-series art was unreachable.
        if p.contains("xbox 360")                              { return "platform-xbox360" }
        if p.contains("xbox series")                           { return "platform-xbox-series" }
        if p.contains("xbox")                                  { return "platform-xbox" }
        if p.contains("recalbox")                              { return "platform-recalbox" }
        if p.contains("steam deck")                            { return "platform-steamdeck" }
        if p.contains("playstation 5") || p == "ps5"           { return "platform-ps5" }
        if p.contains("playstation 4") || p == "ps4"           { return "platform-ps4" }
        if p.contains("playstation 3") || p == "ps3"           { return "platform-ps3" }
        if p == "playstation" || p.contains("playstation 1")
            || p == "ps1" || p == "psx"                        { return "platform-ps1" }
        if p.contains("3ds")                                   { return "platform-3ds" }
        if p.contains("wii u")                                 { return "platform-wiiu" }
        if p.contains("wii")                                   { return "platform-wii" }
        if p.contains("microsoft windows") || p == "pc"
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
