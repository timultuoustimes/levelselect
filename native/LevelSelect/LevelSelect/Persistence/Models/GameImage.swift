import Foundation
import SwiftData

/// An image the USER added to a game — a photo of the copy they owned, a
/// screenshot they took, art they found. Schema V3.
///
/// The first user-generated *bytes* in a store whose trust story was built
/// entirely around text, which is why the surrounding machinery matters as
/// much as the model:
///
/// - **`.externalStorage`** keeps the bytes out of the SQLite row and lets
///   CloudKit mirror them as a CKAsset rather than inlining them in a record.
/// - **Images are downscaled on the way in** (`ImageIngest`), never stored at
///   camera resolution. A 12MP photo is ~4MB; a hundred of those would be a
///   sync bill the user never agreed to and an export nobody can open.
/// - **The export carries them** (base64, per game). "Your library exports to
///   a readable file" is a promise the site and the beta notes both make, and
///   a photo the user added is exactly the kind of thing that must not
///   silently fall out of their backup. Maps still export as links — that
///   remains an honest, documented gap, and it is about *fetched* art rather
///   than something the user made.
/// - **Soft-delete cascades from the game**, so Recently Deleted restores a
///   game with its pictures intact rather than with holes in it.
@Model
final class GameImage {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// Which slot this image is *eligible* for — see `ArtworkRole`. Eligible,
    /// not assigned: what actually fills a role is whatever the game points
    /// at (`Game.pointer(for:)`), so an image can sit in the library unused.
    var roleRaw: String = ArtworkRole.gallery.rawValue

    /// The bytes. Optional because CloudKit requires it, and because a record
    /// can arrive from sync before its asset does.
    @Attribute(.externalStorage) var data: Data?

    /// The user's own words about it, if any. A caption is notebook material:
    /// "the cart I traded away", "final boss, third try".
    var caption: String?

    /// Recorded at ingest so a gallery can lay out before decoding anything,
    /// and so Settings can report what images are costing without loading
    /// every one of them.
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var byteCount: Int = 0

    var addedAt: Date = Date.now
    var game: Game?

    /// The memory this picture belongs to, when it belongs to one. Schema V5.
    ///
    /// Reused rather than given its own model, which is Tim's call and the
    /// cheap one: the ingest path, the export path and — the part that
    /// actually matters — **the CloudKit asset fields are already deployed**,
    /// so a photo of Christmas 1995 costs no new binary field. Build 32 lost a
    /// full promote cycle to `externalStorage` retyping BYTES vs ASSET; not
    /// doing that twice is worth more than a tidy model name.
    var memory: Memory?

    init(id: UUID = UUID(), role: ArtworkRole = .gallery, data: Data? = nil) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.addedAt = .now
        self.roleRaw = role.rawValue
        self.data = data
        self.byteCount = data?.count ?? 0
    }
}

extension GameImage: Identifiable {}

extension GameImage {
    var role: ArtworkRole {
        get { ArtworkRole(rawValue: roleRaw) ?? .gallery }
        set { roleRaw = newValue.rawValue }
    }

    /// The pointer string a `Game` stores to select this image for a role.
    var pointer: String { ArtworkPointer.local(id) }
}

/// The three slots artwork can fill on a game page, plus the loose pile.
///
/// Before this, the app had exactly one artwork idea — "the cover" — and
/// build 31 gave it a picker. Logos and backdrops would have been two more
/// unrelated pickers; naming the *roles* keeps one surface for all of them,
/// and makes user-added images a SOURCE inside it rather than a feature
/// bolted on beside it.
enum ArtworkRole: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The shelf thumbnail. Falls back to the fetched IGDB cover.
    case cover
    /// The header wordmark. Falls back to the game's name as text — always.
    case logo
    /// The band behind the header. Falls back to the blurred cover.
    case backdrop
    /// Not a slot: images kept with the game, shown in Media beside the
    /// screenshots IGDB provides.
    case gallery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover:    "Cover"
        case .logo:     "Logo"
        case .backdrop: "Backdrop"
        case .gallery:  "Gallery"
        }
    }

    var fallbackNote: String {
        switch self {
        case .cover:    "Falls back to the cover from IGDB."
        case .logo:     "Falls back to the game's name in text — always, and at large text sizes."
        case .backdrop: "Falls back to the cover, blurred."
        case .gallery:  "Kept with the game and shown under Media."
        }
    }

    /// Roles a game can point at. `gallery` is a pile, not a slot.
    static var assignable: [ArtworkRole] { [.cover, .logo, .backdrop] }
}

/// What a role resolves to once pointers and fallbacks are applied.
///
/// Views switch on this rather than juggling "URL or Data or neither", which
/// is the shape that produces three slightly-different renderers.
enum ResolvedArtwork: Equatable {
    case remote(URL)
    case local(Data)
    case none

    var isEmpty: Bool { self == .none }
}

/// How a `Game` names the artwork filling a role.
///
/// ONE string per role, holding either a remote URL or a reference to a local
/// `GameImage`. Deliberately not two fields per role: with a URL field and an
/// id field there is always a question of which wins, and every read site has
/// to answer it the same way or they drift. One pointer has no precedence
/// question, and clearing a role is just `nil`.
enum ArtworkPointer {
    static let localScheme = "levelselect-image:"

    static func local(_ id: UUID) -> String { localScheme + id.uuidString }

    /// The local image id this pointer names, if it names one.
    static func localID(_ pointer: String?) -> UUID? {
        guard let pointer, pointer.hasPrefix(localScheme) else { return nil }
        return UUID(uuidString: String(pointer.dropFirst(localScheme.count)))
    }

    /// The remote URL this pointer names, if it names one.
    static func remoteURL(_ pointer: String?) -> URL? {
        guard let pointer, !pointer.hasPrefix(localScheme) else { return nil }
        return URL(string: pointer)
    }
}
