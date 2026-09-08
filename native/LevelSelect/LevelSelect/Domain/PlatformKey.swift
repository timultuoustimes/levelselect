import Foundation

/// One console, one name — the fold from every spelling a platform arrives
/// under to the single word the app uses for it.
///
/// **This lives in `Domain/` because the STORE needs it now.** It was a
/// method on `PlatformShort` in `UI/`, which was fine while folding was only
/// a display concern. `Console` (build 39) makes it an identity concern: a
/// console record is keyed by this name, so "Nintendo Switch 2" from IGDB and
/// "Switch 2" typed by hand have to arrive at one record rather than two.
/// `Persistence` cannot see `UI` — the widget target compiles one and not the
/// other — so the fold moves down here and `PlatformShort.builtinName` calls
/// it. Every existing call site keeps working; nothing about the names changed.
///
/// Pure, so the folding can be tested without a store or a running app.
enum PlatformKey {
    /// The app's own short name for a platform, before the user has a say.
    /// `PlatformShort.name(_:)` applies their renames on top of this.
    static func canonical(_ p: String) -> String {
        switch p {
        // **One computer, whatever it boots.** The app has never had a
        // "Windows" console — a PC is a PC — so a separate Linux one made the
        // operating system the machine for exactly one of the two. Tim,
        // 2026-09-08: *"Linux feels like the odd one out. We don't specify
        // windows PC, so a pc gamer can be playing on windows or Linux."*
        // Steam Deck and Steam Machine stay their own consoles; they are
        // hardware you can hold, not a choice of OS on a box you already own.
        case "PC (Microsoft Windows)", "Linux", "PC (Linux)", "Windows": "PC"
        case "Nintendo Switch": "Switch"
        case "Nintendo Switch 2": "Switch 2"
        case "PlayStation 5": "PS5"
        case "PlayStation 4": "PS4"
        case "PlayStation 3": "PS3"
        case "PlayStation 2": "PS2"
        // IGDB calls the original console simply "PlayStation"; PS1 is
        // clearer beside PS2/PS3 and is what everyone says anyway.
        case "PlayStation": "PS1"
        case "PlayStation Portable": "PSP"
        case "PlayStation Vita", "PlayStation Vita (PS Vita)": "Vita"
        case "Xbox Series X|S", "Xbox Series X/S", "Xbox Series X", "Xbox Series": "Xbox Series"
        case "Xbox One": "Xbox One"
        case "Xbox 360": "Xbox 360"
        case "Nintendo 3DS", "New Nintendo 3DS": "3DS"
        case "Nintendo DS", "Nintendo DSi": "DS"
        case "Wii U": "Wii U"
        case "Nintendo Wii", "Wii": "Wii"
        case "Super Nintendo Entertainment System", "SNES", "Super NES": "SNES"
        case "Nintendo Entertainment System", "NES": "NES"
        case "Family Computer", "Famicom", "Family Computer Disk System": "Famicom"
        case "Super Famicom": "Super Famicom"
        case "Nintendo 64": "N64"
        case "Nintendo GameCube", "GameCube": "GameCube"
        case "Game Boy Advance": "GBA"
        case "Game Boy Color": "GBC"
        case "Sega Mega Drive/Genesis", "Sega Genesis", "Genesis", "Mega Drive": "Genesis"
        case "Sega Master System/Mark III", "Sega Master System": "Master System"
        case "Sega Dreamcast", "Dreamcast": "Dreamcast"
        case "Sega Saturn": "Saturn"
        case "Sega Game Gear", "Game Gear": "Game Gear"
        // Folded together so the Sega CD / Mega-CD choice has one console to
        // apply to rather than two half-shelves. The 32X stays on its own —
        // it is a different device, not another word for this one.
        case "Sega Mega-CD", "Sega CD", "Mega-CD": "Sega CD"
        case "Sega 32X": p
        case "TurboGrafx-16/PC Engine", "TurboGrafx-16": "TurboGrafx-16"
        // **The picture was always a Raspberry Pi.** The art in
        // `platform-recalbox` is a Pi board in a case, logo and all, so the
        // NAME was the part that did not match. Recalbox is one distribution
        // that runs on it, and naming the hardware after one of its operating
        // systems implied the app owed the same courtesy to AYANEO, Anbernic,
        // Retroid and Analogue. Tim, 2026-09-08: *"we rename recalbox to
        // Raspberry Pi to make it fit more people."* Old libraries fold into
        // the new name rather than splitting, which is what this line is for.
        case "Recalbox", "Raspberry Pi", "RetroPie", "Batocera": "Raspberry Pi"
        case "Other", "": "Other"
        default: p
        }
    }
}
