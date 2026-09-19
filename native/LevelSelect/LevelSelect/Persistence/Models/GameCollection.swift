import Foundation
import SwiftData

/// A Plex-style collection of games — either an official compilation/bundle
/// (Batman: Arkham Trilogy) or a personal list (comfort games, soundtracks).
/// CloudKit-compatible: membership is stored as an array of Game id strings
/// (a game can belong to many collections; no fragile many-to-many relationship).
@Model
final class GameCollection {
    // Sync metadata
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var name: String = ""
    var notes: String = ""
    var sortIndex: Int = 0

    /// A bundle (official compilation) groups games that are "inside" it, so its
    /// members can be hidden from the main library. A list (comfort games) is
    /// just a curated grouping and never hides its members.
    var isBundle: Bool = false

    /// **A rule instead of a hand-picked list — a Smart Collection.**
    ///
    /// Nil for an ordinary collection. Otherwise an encoded filter, the same
    /// combination Library already offers: status, system, ownership, tag.
    ///
    /// Tim, asked whether a saved filter should be its own noun: *"I think
    /// saved filters can be smart collections?"* — which is the answer that
    /// costs one field instead of a model, and inherits the Collections tab,
    /// the prompts, the naming and the composite art rather than inventing a
    /// sixth kind of thing for the app to explain.
    var filterRuleRaw: String?


    /// Member game ids (`Game.id.uuidString`).
    var gameIDs: [String] = []

    init(name: String, isBundle: Bool = false, sortIndex: Int = 0) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.isBundle = isBundle
        self.sortIndex = sortIndex
    }

    func contains(_ game: Game) -> Bool { gameIDs.contains(game.id.uuidString) }
}
