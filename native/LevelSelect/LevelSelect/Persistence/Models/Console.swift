import Foundation
import SwiftData

/// A console you own — a record, not a label derived from games.
///
/// **Why this exists.** The systems shelf was a *grouping*: games bucketed by
/// their most-preferred platform, ordered by count, computed from an array of
/// strings. There was no console anywhere in the data model. Tim, 2026-08-31,
/// with four photographs of real game rooms: *"The systems are their portals
/// into the games. Without them, the games don't exist… A system shelf shows
/// the consoles you own… This isn't just a database, it's a connection to a
/// feeling and a history."* In every photograph the games are on shelves and
/// the consoles are the display — lit, arranged, at eye level. This is that
/// instinct taken seriously.
///
/// **What only a record can say.** A Dreamcast you own and have logged nothing
/// for. An N64 you sold in college, which the computed shelf erased along with
/// the games. Genesis games you own physically AND emulate, which one inferred
/// platform string cannot hold. A shelf in the order you would arrange it
/// rather than by descending game count.
///
/// ## Nothing cascades
///
/// The console's ownership is its own. Tim, settling it: *"You can previously
/// own games and still own a console, previously own a console but still own
/// the games, or previously own all of it."* So selling a console says nothing
/// about its games, and selling the games says nothing about the console —
/// the rule games already follow, one level up.
///
/// ## Identity is the folded name
///
/// `platform` holds `PlatformKey.canonical(_:)`, so "Nintendo Switch 2" from
/// IGDB and "Switch 2" typed by hand are one console rather than two. That is
/// the same fold Home's case uses to draw one tile, and the reason the fold
/// moved out of `UI/` into `Domain/`.
///
/// ## What is deliberately NOT here
///
/// **Order.** Build 38 already ships Arrange Systems, which stores the shelf's
/// order in `ThemeSettings.homeSystemsRaw`. A `sortIndex` here would be a
/// second answer to a settled question.
///
/// **A hardware taxonomy.** Model 1 vs Model 2, OLED vs launch, a modded PS2:
/// collectors care enormously and it is a rabbit hole with no floor. Tim:
/// *"Hardware variance should maybe be a text field for now?"* So `variant` is
/// a text field, and the honest half of that idea — which console art to show
/// — already lives in `ThemeSettings.platformIconVariantsData`.
@Model
final class Console {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?
    var userID: UUID?

    /// Which console this is, as `PlatformKey.canonical(_:)` folds it —
    /// "Switch 2", "Genesis", "SNES". One live record per name.
    var platform: String = ""

    /// How you have it: `Ownership` raw values, multi-select, the same
    /// vocabulary a game uses. Tim: *"I both own a Sega Genesis and emulate
    /// Sega Genesis for the games I don't own physically."* Both are true at
    /// once, and until this record existed only one could be inferred.
    var ownership: [String] = []

    /// The ownerships this console has been offered and refused, so the
    /// question is asked once and never again.
    ///
    /// This is the field that makes the creation rules honest rather than
    /// merely convenient. **A physical game does not imply a physical
    /// console** — people buy sealed and display copies for shelves they
    /// cannot play — so a game arriving with an ownership the console lacks
    /// asks instead of assuming. Without somewhere to record "no", it would
    /// ask again on the next game, forever.
    var declinedOwnership: [String] = []

    /// "Model 1", "OLED", "modded, 2TB drive". Free text, on purpose — see
    /// the note above.
    var variant: String?

    /// When it came into your life, if you want to say. The Home shelf's
    /// "order I acquired them" reads this.
    var acquiredAt: Date?

    /// "My brother's." The sentence the spec was written around.
    var notes: String?

    /// Photographs of the hardware. **Ahead of the feature, deliberately.**
    ///
    /// The display case is a real thing people photograph, and this is where
    /// those pictures would live. Reusing `GameImage` rather than inventing a
    /// model means the deployed CKAsset fields already exist, exactly the
    /// reasoning that put `Memory`'s photos there — and a relation that ships
    /// a build early costs an unused optional, where a second schema promote
    /// costs a seed, a diff, a deploy, a purge and a restore.
    @Relationship(deleteRule: .cascade, inverse: \GameImage.console)
    var images: [GameImage]?

    init(id: UUID = UUID(), platform: String = "", ownership: [String] = []) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.platform = platform
        self.ownership = ownership
    }
}
