import Foundation
import SwiftData

/// Something that happened, which the app was not running for. Schema V5.
///
/// Everything else in this store is a record the app made while you used it,
/// which means the library's history begins the day you installed it. Tim's
/// case, and the one to design against:
///
/// > *"Received Sega Genesis Model 2 Columns Bundle, Christmas 1995 or 1996."*
///
/// Nothing existing bends to hold that. `Session` needs a playthrough and a
/// duration, `CompletionEvent` needs a game and describes finishing it, `Run`
/// belongs to the run engine. A memory may have **no game**, may be about
/// **hardware** rather than software, is about an occasion rather than play,
/// and its date may be a **region** rather than an instant.
///
/// The point is bigger than the feature: once entries can predate the install,
/// the app stops being a tracker for what you are playing and becomes a gaming
/// autobiography that reaches back as far as you do. It is also the honest
/// answer to a cold start — a new library is empty and slightly demoralising,
/// and everyone has been playing games for longer than they have had this app.
@Model
final class Memory {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// What happened, in a line. "Got a Sega Genesis for Christmas."
    var title: String = ""
    /// The rest of it, if there is any.
    var body: String?

    // MARK: When — three fields doing three genuinely different jobs

    /// **Exactly what was typed, and what is always displayed.**
    ///
    /// The rule that makes fuzzy dating work: *never re-render the user's
    /// language from structured parts*. A model that round-trips "Christmas
    /// 1995 or 1996" into "Dec 1995 – Jan 1997" has destroyed the entry and
    /// made it slightly wrong in the same step. Machines get the interval
    /// below; people get the sentence they wrote.
    ///
    /// `nil` when the date was *picked* rather than described, because then
    /// the interval reproduces it exactly and storing a copy would only give
    /// the two a chance to disagree. Re-rendering is correct for **precision**
    /// ("May 1995" from a month); verbatim is correct for **uncertainty**.
    var whenText: String?

    /// The earliest and latest instants it could have been. What sorting,
    /// grouping and querying use — and the reason a vague memory can sit in a
    /// timeline at all.
    ///
    /// "Christmas 1995 or 1996" becomes roughly 1 Dec 1995 → 31 Jan 1997. As
    /// evidence arrives the interval narrows: attach the photo of the morning
    /// itself and its EXIF can tighten this to a day. **Narrowing must never
    /// overwrite `whenText`** — "Christmas 1995, confirmed by photo" is the
    /// right outcome; "December 25, 1995" is not.
    var earliest: Date = Date.now
    var latest: Date = Date.now

    /// `day` | `month` | `year`, or nil when no single precision describes it.
    ///
    /// The same vocabulary as `CompletionEvent.datePrecision`, reused rather
    /// than a second one invented beside it. **nil is meaningful**: it is the
    /// disjunction case — "1995 or 1996" is not year-precision, it is two
    /// years, and only `whenText` can say so.
    var precision: String?

    // MARK: What kind of thing it was

    /// `memory`, or an ownership event: `acquired`, `sold`, `traded`, `lost`,
    /// `gifted`, `lent`, `returned`, `broke`.
    ///
    /// **A String rather than a stored enum, deliberately.** CloudKit syncs
    /// between devices on different builds, so a value added by a later build
    /// must not fail to decode on one still running this build. An unknown
    /// kind reads as a plain memory, which is the graceful answer.
    ///
    /// Ownership lives here rather than beside it because *"sold my collection
    /// in college"* is a memory **and** an ownership event — one record seen
    /// from two sides. `Game.ownership` is a chip array, a *current* value,
    /// and it cannot express owning the same thing twice with a gap in the
    /// middle, which is one of the most common collector stories there is.
    var kind: String = "memory"

    /// A place name, and **never an address or coordinates**. Tim's line:
    /// *"Grandma's house is fine; Grandma's address is unnecessarily
    /// specific."*
    ///
    /// The design consequence is exact — do not store coordinates at all. Read
    /// a photo's EXIF only far enough to *offer* a prompt, keep the label
    /// typed in reply, and discard the rest. Reverse geocoding is a network
    /// call, so turning those coordinates into a place name would transmit the
    /// location of someone's childhood home off-device.
    var place: String?

    /// Who was there. `Companion` again, so "who I played with" means one
    /// thing across sessions, finishes and memories.
    var playedWithData: Data?

    /// Optional, and the optionality is the feature — "first LAN party" has
    /// neither a game nor a console.
    var game: Game?

    /// "Sega Genesis". A plain string rather than a hardware entity, on
    /// purpose: it earns the console artwork for free, and it defers the
    /// question of modelling individual copies, which is a much larger thing
    /// than it looks. Ship the chain, not the inventory.
    var platform: String?

    @Relationship(deleteRule: .cascade, inverse: \GameImage.memory)
    var images: [GameImage]?

    init(id: UUID = UUID(),
         title: String = "",
         kind: String = "memory",
         earliest: Date = .now,
         latest: Date = .now,
         precision: String? = "day",
         whenText: String? = nil) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.title = title
        self.kind = kind
        self.earliest = earliest
        self.latest = latest
        self.precision = precision
        self.whenText = whenText
    }
}

extension Memory {
    var companions: [Companion] {
        get { [Companion].decoded(playedWithData) }
        set { playedWithData = newValue.encoded }
    }

    /// What to print. The user's words when there are any, and otherwise the
    /// interval rendered at the precision it actually has.
    var dateText: String {
        if let whenText, !whenText.trimmingCharacters(in: .whitespaces).isEmpty {
            return whenText
        }
        // **UTC, because a memory's date is a calendar fact rather than an
        // instant** — "Christmas 1995" is the same day everywhere, and reading
        // a UTC-midnight stamp in local time turns 2011 into 2010 for anyone
        // west of Greenwich. Same rule the release dates follow, opposite of
        // the local-day rule the journal's sessions follow, and the difference
        // is real: a session is something you did where you were sitting.
        return CompletionEvent.fuzzyText(earliest, precision: precision, timeZone: .gmt)
    }

    /// True when the interval is wider than the precision claims — the
    /// disjunction case, where only the typed words are accurate.
    var isUncertain: Bool { precision == nil }
}
