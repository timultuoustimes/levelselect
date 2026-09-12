import SwiftUI

/// The four things LevelSelect promises on the welcome screen.
///
/// **One list, two surfaces.** The welcome draws all four as rows. Home draws
/// three of them again — as the caption on the empty shelf that makes good on
/// that promise — for as long as the shelf is still empty and the library is
/// still new.
///
/// That is F1, and it is why the strings live here rather than inline in
/// `WelcomeView`. Tim's answer: the first five minutes and the full app should
/// look like one product. They only do if the words are literally the same
/// words, and the only way to guarantee that a year from now is to give them
/// one home and let both screens read from it. Edit a promise here and the
/// welcome and the shelf change together; there is no second copy to forget.
enum AppPromise: CaseIterable {
    case shelf
    case sessions
    case checklist
    case privacy

    var symbol: String {
        switch self {
        case .shelf:     "gamecontroller"
        case .sessions:  "clock"
        case .checklist: "checklist"
        case .privacy:   "lock"
        }
    }

    var title: String {
        switch self {
        case .shelf:     "A shelf, not a spreadsheet"
        case .sessions:  "Sessions time themselves"
        case .checklist: "The game's real checklist"
        case .privacy:   "Yours, privately"
        }
    }

    var body: String {
        switch self {
        case .shelf:
            "Add the games you're actually playing."
        case .sessions:
            "Start from the app, a widget, your watch, or the Lock Screen."
        // Real lists first, generation last — pasting beats generating, and
        // neither the welcome nor the shelf should imply otherwise.
        case .checklist:
            "Import real achievements, paste a guide you trust, or plan it a piece at a time."
        case .privacy:
            "Your device and your own iCloud. No account, no ads, no tracking."
        }
    }

    /// The same promise, said about the shelf that keeps it.
    ///
    /// **Word-for-word was the wrong reading of "one product".** The welcome's
    /// bodies were used verbatim as shelf captions, which works for the first
    /// promise and fails for the other two: Paused got "Start from the app, a
    /// widget, your watch, or the Lock Screen" and Up Next got "Import real
    /// achievements, paste a guide you trust…". Neither says anything about
    /// pausing or queueing. Fable, 2026-09-07: *"a reader who has just seen
    /// the welcome will look for the connection and not find one."*
    ///
    /// The goal was never identical sentences — it was ONE HOME, so there is
    /// no second copy to forget. That survives: both surfaces still read from
    /// this file, and each says the true thing for where it is standing. The
    /// captions keep the promises' subjects — your time, a real checklist — so
    /// the connection is still legible from the welcome.
    var shelfCaption: String? {
        switch self {
        // This one genuinely is the same sentence: the promise is about the
        // shelf, so the shelf can say it unchanged.
        case .shelf:     body
        case .sessions:  "Games you stepped away from. Your time and your place are kept."
        case .checklist: "What you'll play next. Bring its real checklist before you start."
        case .privacy:   nil
        }
    }

    /// The Home shelf that keeps this promise.
    ///
    /// `privacy` returns nil on purpose. It is the one promise that isn't
    /// about a shelf — it is about the whole app — so on Home it closes the
    /// page as a footer, which is also where the welcome puts it. Inventing a
    /// shelf for it would have been the app making something up to fill a
    /// grid, and a promise nailed to the wrong wall stops reading as a promise.
    var shelf: GameStatus? {
        switch self {
        case .shelf:     .playing
        case .sessions:  .paused
        case .checklist: .queued
        case .privacy:   nil
        }
    }

    static func promise(for status: GameStatus) -> AppPromise? {
        allCases.first { $0.shelf == status }
    }

    /// How small a library still counts as "just arrived".
    ///
    /// Above this, Home goes back to drawing only the shelves that have
    /// something on them. The captions are for the stretch between the welcome
    /// and a working shelf — someone who has genuinely settled at five games
    /// does not need to be told what Paused is every time they open the app.
    ///
    /// Five rather than one, because the first thing many people do is add
    /// two or three games in a row and none of that teaches them what the
    /// other shelves are for. It is also low enough that a CSV import clears
    /// it on the first run, which is exactly right: someone arriving with a
    /// backlog has already skipped this part.
    static let newLibraryLimit = 5
}

extension GameStatus {
    /// What this Home shelf says while it is empty and the library is new.
    ///
    /// Three of the four shelves carry a welcome promise, said about THAT
    /// shelf — see `AppPromise.shelfCaption` for why that is not the same
    /// sentence in two of the three. Always Around gets its own line because
    /// no promise fits it, and a shelf left silent beside three captioned ones
    /// reads as a rendering bug rather than as restraint.
    var emptyShelfCaption: String? {
        if let promise = AppPromise.promise(for: self) { return promise.shelfCaption }
        switch self {
        // The status exists because some games have no finish line. Saying so
        // is more use here than any promise would be.
        case .ongoing:
            return "The ones with no ending — a city builder, a world you keep going back to."
        default:
            return nil
        }
    }
}
