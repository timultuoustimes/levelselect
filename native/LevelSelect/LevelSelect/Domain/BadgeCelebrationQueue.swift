import Foundation

/// **A celebration nobody sees didn't happen.**
///
/// The toast and the confetti live at the root of the app, so anything
/// presented over it hides both — and the eight seconds run out behind the
/// sheet. Stopping a session is the case that matters, because the stop sheet
/// is exactly where a session badge gets earned: without this, the one
/// celebration guaranteed to be missed is the one for finishing a session
/// (spec, 09-21).
///
/// Its own type rather than a few properties on `AppNavigator` because the
/// navigator is a singleton with a private `init`, and a rule this fiddly —
/// nesting, unbalanced counts, several badges at once — deserves tests that
/// don't share state with every other test in the suite.
@MainActor
final class BadgeCelebrationQueue {
    /// How many sheets are currently over the root, counted by `lsSheet`.
    private(set) var openSheets = 0
    private var pending: [Badges.Definition] = []
    private let release: ([Badges.Definition]) -> Void

    /// How long to wait after the last sheet closes. A beat, so the paper
    /// doesn't start flying while the sheet is still sliding down over it.
    private let settle: Duration

    init(settle: Duration = .milliseconds(450),
         release: @escaping ([Badges.Definition]) -> Void) {
        self.settle = settle
        self.release = release
    }

    func celebrate(_ badges: [Badges.Definition]) {
        guard !badges.isEmpty else { return }
        if openSheets > 0 { pending += badges } else { release(badges) }
    }

    func sheetOpened() { openSheets += 1 }

    func sheetClosed() {
        // **Never below zero.** `onDisappear` can outnumber `onAppear` — a
        // sheet dismissed while the app is in the background, a view rebuilt
        // underneath one. A negative count would read as "nothing is open"
        // and celebrate underneath the next real sheet.
        openSheets = max(0, openSheets - 1)
        guard openSheets == 0, !pending.isEmpty else { return }
        let waiting = pending
        pending = []
        Task { [settle, release] in
            try? await Task.sleep(for: settle)
            release(waiting)
        }
    }
}
