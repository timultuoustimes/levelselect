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
        // **The Disk System is not the Famicom.** It folded into it, so a
        // game listing both arrived as two chips reading "Famicom" — with
        // different pictures, because `assetName` has always told them apart.
        // Tim, 2026-09-08: *"famicom is twice, but I think one is famicom one
        // is an attachment console that has a different name."*
        case "Family Computer Disk System", "Famicom Disk System",
             "Family Computer Disk System (FDS)": "Famicom Disk System"
        case "Family Computer", "Famicom": "Famicom"
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
        // Atari. IGDB spells them out in full; people say the number.
        case "Atari 2600", "Atari VCS", "Atari 2600+": "Atari 2600"
        case "Atari 5200": "Atari 5200"
        case "Atari 7800", "Atari 7800 ProSystem": "Atari 7800"
        case "Lynx", "Atari Lynx": "Atari Lynx"
        case "Jaguar", "Atari Jaguar", "Atari Jaguar CD": "Atari Jaguar"
        // Commodore. IGDB's name for the 8-bit machine is a slash-separated
        // list of three models; the C64 is the one anyone means. The CD32 is
        // folded before the bare Amiga, the same way the Famicom Disk System
        // is folded before the Famicom.
        case "Amiga CD32", "CD32": "Amiga CD32"
        case "Commodore C64/128/MAX", "Commodore 64", "C64", "C64/128": "Commodore 64"
        case "Commodore Amiga", "Amiga", "Amiga 500": "Amiga"
        // SNK. IGDB writes the home console "Neo Geo AES"; people say "Neo
        // Geo" and mean that one, so the bare name folds into it. The mono
        // Pocket keeps its own name — it shares the Color's picture, not its
        // identity.
        case "Neo Geo AES", "Neo Geo", "NeoGeo", "SNK Neo Geo AES": "Neo Geo AES"
        case "Neo Geo MVS", "SNK Neo Geo MVS": "Neo Geo MVS"
        case "Neo Geo Pocket Color": "Neo Geo Pocket Color"
        // The 1970s and 80s, and the two home computers people played on.
        case "Mattel Intellivision", "Intellivision": "Intellivision"
        case "ColecoVision", "Coleco Vision": "ColecoVision"
        case "Vectrex", "GCE Vectrex": "Vectrex"
        case "Sinclair ZX Spectrum", "ZX Spectrum", "ZX Spectrum 48K": "ZX Spectrum"
        // MSX2 and the Turbo R fold into MSX: successive revisions of one
        // standard, and one picture between them.
        case "MSX", "MSX2", "MSX2+", "MSX Turbo R": "MSX"
        case "3DO Interactive Multiplayer", "3DO", "Panasonic 3DO": "3DO"
        case "WonderSwan Color", "Bandai WonderSwan Color": "WonderSwan Color"
        case "WonderSwan", "Bandai WonderSwan": "WonderSwan"
        // IGDB says "Arcade" and so does everyone else.
        case "Arcade", "Arcade Cabinet": "Arcade"
        case "Other", "": "Other"
        default: p
        }
    }
}
