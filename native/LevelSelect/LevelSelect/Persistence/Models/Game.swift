import Foundation
import SwiftData

/// A game in the library (legacy `library[]`).
/// CloudKit-compatible: no unique constraints, every property optional or
/// inline-defaulted, relationships optional/defaulted.
@Model
final class Game {
    // Sync metadata
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    // Identity & metadata
    var name: String = ""
    var summary: String?
    var notes: String = ""
    var igdbID: Int?
    var igdbSlug: String?
    var firstReleaseDate: Date?
    var franchise: String?
    var coverURLString: String?
    var coverImageID: String?
    /// A cover the user chose in place of the fetched one (their own image, a
    /// different official release, community art). Schema V2 — the art the
    /// box had when THEY owned it is part of the memory. Wins over
    /// `coverURLString` wherever a cover is drawn — read `displayCoverURLString`,
    /// never `coverURLString`, when rendering.
    ///
    /// Since V3 this is an `ArtworkPointer`: still a plain http(s) URL in the
    /// usual case, but it may instead name a local `GameImage`.
    var coverOverrideURLString: String?

    // MARK: Artwork roles (Schema V3)
    //
    // One pointer per role, each an `ArtworkPointer` — a remote URL or a
    // local image reference. Nil means "fall back", and every fallback is
    // defined by `ArtworkRole.fallbackNote`.

    /// The header wordmark. Nil renders the game's name as text, which is
    /// also what happens at accessibility type sizes regardless.
    var logoURLString: String?
    /// The band behind the header. Nil falls back to the cover, blurred.
    var backdropURLString: String?

    /// The cover to DRAW: the user's choice when they've made one, the
    /// fetched art otherwise. Fetch/refresh paths keep writing
    /// `coverURLString`, so Fix Match and the fill pass can never overwrite a
    /// chosen cover.
    ///
    /// Returns nil for a LOCAL chosen cover — bytes have no URL. Grid-shaped
    /// surfaces should read `resolvedArtwork(.cover)` instead; this stays for
    /// the many call sites that only ever want a URL, and for the widget
    /// bridge, which can't carry a SwiftData object across the process line.
    var displayCoverURLString: String? {
        if let remote = ArtworkPointer.remoteURL(coverOverrideURLString) {
            return remote.absoluteString
        }
        // A local override deliberately does NOT fall through to the fetched
        // cover: the user picked a picture, and quietly showing a different
        // one because this accessor can't express theirs would be a lie.
        if ArtworkPointer.localID(coverOverrideURLString) != nil { return nil }
        return coverURLString
    }

    /// The pointer for a role, or nil when nothing is chosen.
    func pointer(for role: ArtworkRole) -> String? {
        switch role {
        case .cover:    coverOverrideURLString
        case .logo:     logoURLString
        case .backdrop: backdropURLString
        case .gallery:  nil
        }
    }

    func setPointer(_ pointer: String?, for role: ArtworkRole) {
        switch role {
        case .cover:    coverOverrideURLString = pointer
        case .logo:     logoURLString = pointer
        case .backdrop: backdropURLString = pointer
        case .gallery:  break   // a pile, not a slot
        }
    }

    /// What actually fills a role right now, including its fallback.
    ///
    /// The ONE place this question is answered. Every render site calls here
    /// rather than reasoning about pointers, so a change to a fallback rule
    /// lands everywhere at once.
    func resolvedArtwork(_ role: ArtworkRole) -> ResolvedArtwork {
        let pointer = pointer(for: role)
        if let localID = ArtworkPointer.localID(pointer),
           let image = liveImages.first(where: { $0.id == localID }),
           let data = image.data {
            return .local(data)
        }
        if let remote = ArtworkPointer.remoteURL(pointer) {
            return .remote(remote)
        }
        switch role {
        case .cover:
            return coverURLString.flatMap(URL.init(string:)).map { .remote($0) } ?? .none
        case .backdrop:
            // Falls back to whatever the cover resolves to, blurred by the
            // view. Recursion is safe: `.cover` never falls back to a role.
            return resolvedArtwork(.cover)
        case .logo, .gallery:
            // A logo has no image fallback ON PURPOSE — the name in text is
            // the fallback, and that belongs to the view.
            return .none
        }
    }

    /// Images that haven't been soft-deleted, newest first.
    var liveImages: [GameImage] {
        (images ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.addedAt > $1.addedAt }
    }

    func liveImages(role: ArtworkRole) -> [GameImage] {
        liveImages.filter { $0.role == role }
    }

    // User state
    var status: GameStatus = GameStatus.backlog
    var pinned: Bool = false
    var rating: Int?          // consolidated game-level (1–5)
    var review: String?
    var addedAt: Date = Date.now
    var currentPlaythroughID: UUID?
    /// Per-game tracker display override; nil = follow the library default.
    var trackerDisplayRaw: String?
    /// Overrides the library-wide "Show item hints" for this game alone.
    /// Nil follows the global setting — blind for the game you're savouring,
    /// hints on everywhere else.
    var showItemHintsOverride: Bool?

    // Value metadata arrays
    var platforms: [String] = []
    /// How the game is owned (raw `Ownership` values; multi-select).
    var ownership: [String] = []
    var userTags: [String] = []
    var genres: [String] = []
    var themes: [String] = []
    var gameModes: [String] = []
    var playerPerspectives: [String] = []
    var developers: [String] = []
    var publishers: [String] = []

    // Relationships — all optional (CloudKit requires optional relationships).
    @Relationship(deleteRule: .cascade, inverse: \Playthrough.game)
    var playthroughs: [Playthrough]?
    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.game)
    var completionEvents: [CompletionEvent]?
    @Relationship(deleteRule: .cascade, inverse: \GameMap.game)
    var maps: [GameMap]?
    @Relationship(deleteRule: .cascade, inverse: \TrackerSchemaRecord.game)
    var trackerSchema: TrackerSchemaRecord?
    @Relationship(deleteRule: .cascade, inverse: \GameVideo.game)
    var videos: [GameVideo]?
    /// The user's own notes and renames for this game's tracker items, kept
    /// OUT of the schema blob so they merge per item instead of whole. See
    /// TrackerItemDetail. Schema V2.
    @Relationship(deleteRule: .cascade, inverse: \TrackerItemDetail.game)
    var trackerItemDetails: [TrackerItemDetail]?
    /// Images the user added. Schema V3. Cascade so a permanent delete takes
    /// the bytes with it. A SOFT delete stamps only the game — its images
    /// stay untouched and come back with it, which is why Recently Deleted
    /// restores a game with its pictures rather than holes.
    @Relationship(deleteRule: .cascade, inverse: \GameImage.game)
    var images: [GameImage]?

    init(
        id: UUID = UUID(),
        name: String,
        status: GameStatus = .backlog,
        notes: String = "",
        addedAt: Date = .now,
        pinned: Bool = false
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.notes = notes
        self.status = status
        self.pinned = pinned
        self.addedAt = addedAt
    }
}
