import Foundation
import SwiftData

/// The person whose shelf this is.
///
/// Home is plural — twenty covers, several statuses, no single game to build
/// a page around. What unites it is not a game but **whose it is**, which is
/// what this record exists to say.
///
/// ## Why not the existing `Profile`
///
/// There is already a `Profile` in the schema. It is dead code — the schema
/// seeder's own comment calls it "a never-used `Profile`" — and it carries
/// `appleUserIdentifier` and `email` under a doc comment reading "The
/// signed-in user", left from the web-app era. CloudKit is additive-only, so
/// those fields can never be removed. Reusing that record would mean an app
/// whose central promise is "no account to make, nothing to sign up for"
/// keeping account fields in its schema permanently.
///
/// `Profile` stays where it is, unused. This is the profile the app actually
/// has, and it holds nothing that implies an account.
///
/// ## Everything here is decoration, deliberately
///
/// Nothing reads these values but the profile itself. A handle is your name
/// written in the front of a notebook — it opens nothing, logs into nothing,
/// and is shown to nobody. That was a choice: a platform plus a handle is most
/// of a deep link, and "Play" could have opened the eShop or Steam, but that
/// is a much larger and platform-specific feature.
///
/// The one handle that DOES work is deliberately not here. A RetroAchievements
/// username is a credential that fetches your unlocks; it lives in the
/// Keychain, device-only, never synced, and must not be folded in with these.
@Model
final class PlayerProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// What you'd like to be called. Nil until someone types something.
    var displayName: String?

    /// A small avatar, stored inline.
    ///
    /// **Not `@Attribute(.externalStorage)`, on purpose.** That attribute picks
    /// its CloudKit field by size at write time — inline values land in a
    /// BYTES field and large ones in an ASSET — so the schema needs BOTH, and
    /// creating both means seeding two images straddling the threshold. Build
    /// 32 learned that the hard way across three Development resets when a
    /// 121 KB logo failed forever against a schema that only had the ASSET
    /// field.
    ///
    /// An avatar has no reason to be large. `ImageIngest` downscales it to a
    /// few tens of KB, which sits comfortably inside a CloudKit record and
    /// needs exactly one plain BYTES field.
    var avatarData: Data?

    /// How the name on Home is colored: nil or "" plain, "accent" to follow
    /// the accent as it changes, otherwise a hex.
    ///
    /// Per-profile rather than per-device, because it is part of how you look
    /// rather than a preference of this phone — the whole point of the profile
    /// is that it is the same you on every device.
    var nameColorRaw: String?

    /// Show the handle instead of a typed name, and keep showing it.
    ///
    /// Distinct from the editor's "Use …" button, which COPIES the handle into
    /// the name once. This LINKS them: rename the handle and the name follows.
    /// Both are worth having — one is a shortcut, one is a decision.
    var useHandleAsName: Bool = false

    /// Your handles, as JSON `[service: handle]`.
    ///
    /// One field rather than one per service, the same shape as
    /// `statusColorsData` — so adding GOG or itch.io later costs no schema
    /// change at all.
    var handlesData: Data?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

extension PlayerProfile {
    /// The name Home should draw: the linked handle, or the typed name.
    ///
    /// Falls back to the typed name when the link is on but there is no handle
    /// to link to — otherwise turning the toggle on before adding a handle
    /// makes the header vanish, which reads as having lost the profile.
    var resolvedDisplayName: String? {
        if useHandleAsName,
           let handle = groupedHandles
            .max(by: { $0.services.count < $1.services.count })?.handle,
           !handle.isEmpty {
            return handle
        }
        let typed = (displayName ?? "").trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? nil : typed
    }

    /// Handles keyed by `GamerService.rawValue`, blank entries dropped.
    var handles: [String: String] {
        get {
            guard let handlesData,
                  let map = try? JSONDecoder().decode([String: String].self, from: handlesData)
            else { return [:] }
            return map.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        set {
            let cleaned = newValue
                .mapValues { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.value.isEmpty }
            handlesData = cleaned.isEmpty ? nil : try? JSONEncoder().encode(cleaned)
        }
    }

    /// The handles as the profile should DRAW them: one row per distinct
    /// handle, carrying every service that uses it.
    ///
    /// Tim's rule, and it is the whole design in one line: *"it shouldn't list
    /// the same thing 4 times if they use the handle across all of them, and
    /// there shouldn't be blank spaces if they don't put any."*
    ///
    /// Someone whose Steam, Xbox and PSN names all match sees that name once
    /// with three marks beside it, not the same word three times. Someone who
    /// filled in one service sees one line — never a form with gaps, because
    /// an empty scaffold reads as unfinished rather than personal.
    var groupedHandles: [(handle: String, services: [HandleService])] {
        Dictionary(grouping: handles.keys.compactMap(HandleService.init(key:))) {
            handles[$0.key] ?? ""
        }
        .map { (handle: $0.key, services: $0.value.sorted { $0.order < $1.order }) }
        .sorted { ($0.services.first?.order ?? 0) < ($1.services.first?.order ?? 0) }
    }
}

/// A service a handle belongs to: one the app knows, or one you named.
///
/// Custom services cost NO schema change. Handles are a single JSON blob keyed
/// by service, and a blob takes any key — so "Apple Arcade" is stored under
/// `custom:Apple Arcade` beside `steam` and nothing about the record changes.
/// Which matters, because the list of places people play is not something this
/// app can finish guessing: Apple Arcade alone carries Balatro, Dead Cells,
/// Dredge and Slay the Spire.
enum HandleService: Hashable, Identifiable, Sendable {
    case builtin(GamerService)
    case custom(String)

    /// Storage key. Built-ins keep their bare raw value so existing profiles
    /// keep working untouched.
    var key: String {
        switch self {
        case .builtin(let s): s.rawValue
        case .custom(let name): "custom:\(name)"
        }
    }

    var id: String { key }

    var label: String {
        switch self {
        case .builtin(let s): s.label
        case .custom(let name): name
        }
    }

    /// Built-ins in their declared order; anything named by hand sorts after,
    /// alphabetically, so a list of your own additions is at least stable.
    var order: Int {
        switch self {
        case .builtin(let s): s.order
        case .custom: GamerService.allCases.count
        }
    }

    init?(key: String) {
        if key.hasPrefix("custom:") {
            let name = String(key.dropFirst("custom:".count))
            guard !name.isEmpty else { return nil }
            self = .custom(name)
        } else if let builtin = GamerService(rawValue: key) {
            self = .builtin(builtin)
        } else {
            return nil
        }
    }

    static var builtins: [HandleService] { GamerService.allCases.map(HandleService.builtin) }
}

/// Services a handle can belong to. String-raw, so adding one costs no schema
/// version — the handles are a single JSON field, not a column each.
enum GamerService: String, CaseIterable, Identifiable, Sendable {
    case nintendo, playstation, xbox, steam, epic, gog, itch, discord

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nintendo:    "Nintendo"
        case .playstation: "PlayStation"
        case .xbox:        "Xbox"
        case .steam:       "Steam"
        case .epic:        "Epic"
        case .gog:         "GOG"
        case .itch:        "itch.io"
        case .discord:     "Discord"
        }
    }

    /// Display order, roughly by how likely someone is to have one.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
