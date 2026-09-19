import Foundation

/// The consoles that go by more than one name, and what those names are.
///
/// `PlatformShort.name` collapses IGDB's many spellings to one short name per
/// machine. For most consoles that is uncontroversial — every spelling of a
/// GameCube is a GameCube. For a handful it is not, and the app was quietly
/// picking a side:
///
/// - **Region.** "Sega Mega Drive/Genesis" is one machine with two names
///   depending on where you grew up. Showing Genesis to someone who owned a
///   Mega Drive is the app telling them what their own console was called.
/// - **Habit.** Tim calls the NES "Nintendo" and the SNES "Super Nintendo".
///   Neither is wrong; the abbreviation is just the one the app happened to
///   prefer.
///
/// **Fixed pairs, not a free text field.** Statuses take any words you like
/// because a status is a category you invented for yourself. A console is a
/// physical object with a small number of real names, and a free field there
/// would invite typos that then split one shelf into two — "Mega Drive" and
/// "Mega drive" grouping separately is a worse outcome than the wrong default.
///
/// Deliberately NOT here: Famicom and Super Famicom. Those are different
/// machines from the NES and SNES, not different names for them, and merging
/// them would lose a distinction someone with an import collection cares about.
/// Nor the 32X, which is its own device rather than another word for the Mega
/// Drive.
enum PlatformNaming {

    /// Default short name → every name that machine legitimately goes by, the
    /// app's default first.
    ///
    /// Keyed on the SHORT name rather than the stored IGDB string, so one
    /// entry covers all the spellings `PlatformShort.name` already folds
    /// together — a library holding "Sega Genesis" and "Mega Drive" as
    /// separate strings is one console here, which is the point.
    static let alternatives: [String: [String]] = [
        // Region splits: the same hardware, sold under two names.
        "Genesis":       ["Genesis", "Mega Drive"],
        "Master System": ["Master System", "Mark III"],
        "TurboGrafx-16": ["TurboGrafx-16", "PC Engine"],
        "Sega CD":       ["Sega CD", "Mega-CD"],
        // Habit: an abbreviation the app preferred, and the name people say.
        "NES":           ["NES", "Nintendo"],
        "SNES":          ["SNES", "Super Nintendo"],
        // The source already admits this one is an editorial call — IGDB says
        // "PlayStation", the app says PS1 because it reads clearly beside PS2.
        "PS1":           ["PS1", "PlayStation"],
        "PC":            ["PC", "Windows"],
        "Vita":          ["Vita", "PS Vita"],
        "Xbox Series":   ["Xbox Series", "Xbox Series X|S"],
    ]

    /// What the machine is, as opposed to what you call it.
    ///
    /// The settings row needs a label that does not change when the choice
    /// does — labelling the row "Genesis" and setting it to "Genesis" reads as
    /// a bug, and labelling it "Genesis" while it is set to "Mega Drive" reads
    /// as a contradiction. The hardware's full name is the one thing in the
    /// row that is not up for debate.
    static let hardware: [String: String] = [
        "Genesis":       "Mega Drive / Genesis",
        "Master System": "Master System / Mark III",
        "TurboGrafx-16": "TurboGrafx-16 / PC Engine",
        "Sega CD":       "Mega-CD / Sega CD",
        "NES":           "Nintendo Entertainment System",
        "SNES":          "Super Nintendo Entertainment System",
        "PS1":           "Sony PlayStation",
        "PC":            "Windows PC",
        "Vita":          "PlayStation Vita",
        "Xbox Series":   "Xbox Series X and S",
    ]

    static func hardwareName(for short: String) -> String {
        hardware[short] ?? short
    }

    /// Stable order for the settings screen. Dictionaries have none, and a
    /// list that reshuffles between visits is a list nobody can find anything
    /// in twice.
    static let order: [String] = [
        "NES", "SNES", "PS1", "Genesis", "Master System",
        "Sega CD", "TurboGrafx-16", "PC", "Vita", "Xbox Series",
    ]

    /// The default — the first name listed, which is what the app shipped.
    static func defaultName(for short: String) -> String {
        alternatives[short]?.first ?? short
    }

    /// Whether `chosen` is a name this console actually goes by.
    ///
    /// Every read is validated rather than trusted. The value arrives from
    /// CloudKit, and a build that adds a name — or removes one — must not
    /// leave an older device rendering a string it no longer offers, or a
    /// newer one rendering something a corrupted record invented.
    static func isValid(_ chosen: String, for short: String) -> Bool {
        alternatives[short]?.contains(chosen) ?? false
    }

    /// The name to display, given what the user picked.
    static func resolved(_ short: String, overrides: [String: String]) -> String {
        guard let chosen = overrides[short], isValid(chosen, for: short) else { return short }
        return chosen
    }

    /// Drops entries that name nothing, so a stored map cannot grow stale
    /// keys forever. Used on the way in and on the way out.
    static func sanitized(_ overrides: [String: String]) -> [String: String] {
        overrides.filter { isValid($0.value, for: $0.key) && $0.value != defaultName(for: $0.key) }
    }
}
