import Foundation

/// A prompt for a collection, with a number attached.
///
/// "Make a list" produces nothing. "Pick six games that made you" produces a
/// list, because the count is a constraint and a constraint is what turns a
/// blank page into a decision. That is the entire idea: these are questions,
/// not folders.
///
/// The count is a *prompt*, deliberately not a limit — a collection created
/// from a template is an ordinary collection afterwards, and nothing stops
/// someone putting seven in a six. Enforcing it (or showing "4 of 6 filled"
/// later) would mean storing the target on `GameCollection`, which is a new
/// stored property and therefore a Schema V3. Not worth a migration for a
/// number that has already done its work by the time the list exists.
struct CollectionTemplate: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case identity   = "Who You Are"
        case time       = "Where the Time Went"
        case hardware   = "Hardware & Shelves"
        case waiting    = "Anticipation"
        case opinions   = "Opinions"
        case occasions  = "Occasions"
        case unfinished = "Unfinished Business"

        /// A hue per section, so a long page of prompts reads as places rather
        /// than one grey wall. Fixed rather than themed: these are the app's
        /// own furniture and shouldn't all turn one colour with the accent.
        var tint: (r: Double, g: Double, b: Double) {
            switch self {
            case .identity:   (0.58, 0.36, 0.98)   // violet
            case .time:       (0.20, 0.65, 0.85)   // teal
            case .hardware:   (0.85, 0.55, 0.25)   // amber
            case .waiting:    (0.35, 0.55, 0.95)   // blue
            case .opinions:   (0.88, 0.35, 0.42)   // red
            case .occasions:  (0.30, 0.72, 0.48)   // green
            case .unfinished: (0.62, 0.62, 0.70)   // slate
            }
        }
    }

    /// How a template can offer a starting point from the user's own library.
    ///
    /// The thing a tracker can do that a list app can't: this app times
    /// sessions and knows what you own, so it can answer some of its own
    /// questions. Only ever a starting point — every one of these is a first
    /// draft the user edits, never a finished list.
    enum Seed: String, Sendable {
        case mostPlayed
        case singleSitting
        case physicalRetro
        case emulatedOnly
        case backlog
        case longestHeld
        case neverStarted
        case unreleasedWishlist
    }

    /// Icons lean on shared gaming furniture rather than any one game's:
    /// hourglasses, cartridges, potions, a d-pad, a trophy. The things that
    /// have meant the same thing across forty years of games.
    let id: String
    let name: String
    let prompt: String
    let slots: Int
    let group: Group
    let systemImage: String
    var seed: Seed?

    /// The note the created collection carries, so the question survives past
    /// the moment of creation — otherwise you come back in a month to a list
    /// called "One Sitting" and no memory of what qualified.
    var notes: String { "\(prompt) (\(slots))" }
}

extension CollectionTemplate {
    static let all: [CollectionTemplate] = [
        // ── Who you are
        .init(id: "made-me", name: "Six That Made Me",
              prompt: "The games that formed your taste — not your favourites",
              slots: 6, group: .identity, systemImage: "person.text.rectangle"),
        .init(id: "the-shelf", name: "The Shelf",
              prompt: "If you could keep only nine, forever",
              slots: 9, group: .identity, systemImage: "books.vertical"),
        .init(id: "only-one", name: "If You Only Play One",
              prompt: "Your single recommendation per genre",
              slots: 5, group: .identity, systemImage: "star.circle"),

        // ── Where the time went
        .init(id: "hundred-hours", name: "The Hundred-Hour Club",
              prompt: "Where your time has really gone",
              slots: 6, group: .time, systemImage: "hourglass", seed: .mostPlayed),
        .init(id: "one-sitting", name: "One Sitting",
              prompt: "Finished start to end without getting up",
              slots: 4, group: .time, systemImage: "moon.zzz", seed: .singleSitting),
        .init(id: "comfort-reruns", name: "Comfort Reruns",
              prompt: "The ones you restart instead of finishing",
              slots: 6, group: .time, systemImage: "arrow.counterclockwise"),
        .init(id: "first-loves", name: "First Loves",
              prompt: "The earliest games you remember finishing",
              slots: 6, group: .time, systemImage: "seal"),

        // ── Hardware & shelves
        .init(id: "cartridge-shelf", name: "Cartridge Shelf",
              prompt: "Physical retro you genuinely own",
              slots: 9, group: .hardware, systemImage: "opticaldisc", seed: .physicalRetro),
        .init(id: "emulated-only", name: "Emulated Only",
              prompt: "You'll never hold a copy, and that's fine",
              slots: 6, group: .hardware, systemImage: "cpu", seed: .emulatedOnly),
        .init(id: "launch-window", name: "Launch Window",
              prompt: "Bought on day one, with the console",
              slots: 4, group: .hardware, systemImage: "shippingbox.fill"),

        // ── Anticipation
        .init(id: "worth-the-wait", name: "Worth the Wait",
              prompt: "Announced, delayed, delayed again — and still landed",
              slots: 6, group: .waiting, systemImage: "calendar.badge.clock"),
        .init(id: "midnight-launch", name: "Midnight Launch",
              prompt: "You stood in an actual queue for it",
              slots: 4, group: .waiting, systemImage: "figure.stand.line.dotted.figure.stand"),
        .init(id: "worth-paying-early", name: "Worth Paying Early",
              prompt: "Pre-ordered and never regretted it",
              slots: 4, group: .waiting, systemImage: "checkmark.seal"),
        .init(id: "preorder-regrets", name: "Pre-order Regrets",
              prompt: "Paid early. Wished you hadn't",
              slots: 4, group: .waiting, systemImage: "creditcard.trianglebadge.exclamationmark"),
        .init(id: "still-waiting", name: "Still Waiting",
              prompt: "Announced, and you're still waiting",
              slots: 4, group: .waiting, systemImage: "clock.badge.questionmark",
              seed: .unreleasedWishlist),
        .init(id: "day-one-every-time", name: "Day One, Every Time",
              prompt: "The series you buy without reading a review",
              slots: 4, group: .waiting, systemImage: "bolt.horizontal"),

        // ── Opinions
        .init(id: "deserved-better", name: "Deserved Better",
              prompt: "Flopped, and shouldn't have",
              slots: 6, group: .opinions, systemImage: "heart.slash.fill"),
        .init(id: "won-me-over", name: "Won Me Over Late",
              prompt: "Didn't click until hours in",
              slots: 4, group: .opinions, systemImage: "arrow.uturn.up"),
        .init(id: "oversold", name: "I Oversold This",
              prompt: "You recommended it too hard, too often",
              slots: 4, group: .opinions, systemImage: "megaphone.fill"),
        .init(id: "no-regret-drop", name: "Dropped Without Regret",
              prompt: "Walked away and never looked back",
              slots: 4, group: .opinions, systemImage: "xmark.bin"),

        // ── Occasions
        .init(id: "two-controllers", name: "Two Controllers",
              prompt: "Better with someone on the sofa",
              slots: 6, group: .occasions, systemImage: "gamecontroller"),
        .init(id: "rainy-sunday", name: "Rainy Sunday",
              prompt: "The whole-day games",
              slots: 4, group: .occasions, systemImage: "cloud.rain.fill"),
        .init(id: "background-games", name: "Background Games",
              prompt: "Played while listening to something else",
              slots: 4, group: .occasions, systemImage: "headphones"),

        // ── Unfinished business
        .init(id: "guilt-pile", name: "The Guilt Pile",
              prompt: "Backlog games you honestly intend to play",
              slots: 6, group: .unfinished, systemImage: "tray.full", seed: .backlog),
        .init(id: "one-day", name: "One Day",
              prompt: "You'll never get to these, and won't delete them either",
              slots: 6, group: .unfinished, systemImage: "infinity"),
        // Deliberately the mirror of The Guilt Pile: that one leads with what
        // you added last week, this one with what has been sitting there for
        // years. Same shelf, opposite ends, and the two say different things.
        .init(id: "longest-held", name: "Longest on the Pile",
              prompt: "Still unplayed, and it's been there the longest",
              slots: 6, group: .unfinished, systemImage: "calendar.badge.exclamationmark",
              seed: .longestHeld),
        .init(id: "lets-be-real", name: "Let's Be Real",
              prompt: "Owned for over a year. Never once started",
              slots: 6, group: .unfinished, systemImage: "eye.trianglebadge.exclamationmark",
              seed: .neverStarted),
    ]

    static func grouped() -> [(group: Group, templates: [CollectionTemplate])] {
        Group.allCases.compactMap { group in
            let items = all.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }
}
