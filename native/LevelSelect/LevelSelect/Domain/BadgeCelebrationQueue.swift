import Foundation

/// **A celebration nobody sees didn't happen.**
///
/// The toast and the confetti live at the root of the app, so anything
/// presented over it hides both — and the eight seconds run out behind it.
///
/// **Anything, not just sheets.** This first counted only sheets that go
/// through `lsSheet`, on the theory that the stop sheet was where a session
/// badge gets earned. It isn't: stopping a session asks "What happened?" in an
/// *alert*, and so does the release reminder when a wishlist game is added.
/// Fable watched a five-badge toast live and expire under that alert on both
/// the phone and the iPad (build 40 runtime assessment, 09-21). So the queue
/// now also asks whether anything at all is presented over the root — sheet,
/// alert, confirmation dialog, full-screen cover — through `isCovered`, which
/// the app answers from the window. Nothing has to be wired up at the 31
/// places that present one.
///
/// Sheets still report themselves, because a sheet closing is an event and an
/// alert closing is not: when a badge is waiting behind something that
/// doesn't say when it's gone, the queue looks again every `pollInterval`
/// until the screen is clear.
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
    /// Whether something the sheet count can't see is over the root.
    private let isCovered: () -> Bool
    private var waiting: Task<Void, Never>?

    /// How long to wait once the screen is clear. A beat, so the paper doesn't
    /// start flying while a sheet or an alert is still animating away.
    private let settle: Duration
    /// How often to look again while something that doesn't announce its own
    /// dismissal is in the way.
    private let pollInterval: Duration

    init(settle: Duration = .milliseconds(450),
         pollInterval: Duration = .milliseconds(400),
         isCovered: @escaping () -> Bool = { false },
         release: @escaping ([Badges.Definition]) -> Void) {
        self.settle = settle
        self.pollInterval = pollInterval
        self.isCovered = isCovered
        self.release = release
    }

    private var covered: Bool { openSheets > 0 || isCovered() }

    func celebrate(_ badges: [Badges.Definition]) {
        guard !badges.isEmpty else { return }
        if covered {
            pending += badges
            waitUntilClear()
        } else {
            release(badges)
        }
    }

    func sheetOpened() { openSheets += 1 }

    func sheetClosed() {
        // **Never below zero.** `onDisappear` can outnumber `onAppear` — a
        // sheet dismissed while the app is in the background, a view rebuilt
        // underneath one. A negative count would read as "nothing is open"
        // and celebrate underneath the next real sheet.
        openSheets = max(0, openSheets - 1)
        if !pending.isEmpty { waitUntilClear() }
    }

    /// One watcher at a time. It releases everything waiting once the screen
    /// has been clear for `settle` — checked twice, so a sheet that opens
    /// during the settle still holds the badge back.
    private func waitUntilClear() {
        guard waiting == nil else { return }
        waiting = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.covered {
                    try? await Task.sleep(for: self.pollInterval)
                    continue
                }
                try? await Task.sleep(for: self.settle)
                guard !self.covered else { continue }
                let ready = self.pending
                self.pending = []
                self.waiting = nil
                if !ready.isEmpty { self.release(ready) }
                return
            }
        }
    }
}
