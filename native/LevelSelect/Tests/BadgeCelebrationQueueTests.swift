import Testing
import Foundation
@testable import LevelSelect

/// The rule that a badge earned under a sheet waits for the sheet, rather
/// than celebrating where nobody can see it (spec, 09-21).
@MainActor
struct BadgeCelebrationQueueTests {

    /// Collects what the queue lets through. `settle` is a twitch rather than
    /// the real beat, so a test of the rule isn't a test of the clock.
    private final class Spy {
        var released: [Badges.Definition] = []
        var ids: [String] { released.map(\.id) }
    }

    /// Stands in for the window: true while something the sheet count can't
    /// see — an alert — is over the root.
    private final class Cover { var up = false }

    private func make(cover: Cover = Cover()) -> (BadgeCelebrationQueue, Spy) {
        let spy = Spy()
        let queue = BadgeCelebrationQueue(settle: .milliseconds(1), pollInterval: .milliseconds(1),
                                          isCovered: { cover.up }) { spy.released += $0 }
        return (queue, spy)
    }

    /// Long enough for a 1ms settle to have fired.
    private func letItSettle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    private var aBadge: Badges.Definition { Badges.catalog[0] }
    private var another: Badges.Definition { Badges.catalog[1] }

    @Test("With nothing presented, a badge celebrates straight away")
    func celebratesImmediately() {
        let (queue, spy) = make()
        queue.celebrate([aBadge])
        #expect(spy.ids == [aBadge.id])
    }

    @Test("A badge earned under a sheet waits until the sheet closes")
    func waitsForTheSheet() async {
        let (queue, spy) = make()
        queue.sheetOpened()
        queue.celebrate([aBadge])
        #expect(spy.released.isEmpty)

        queue.sheetClosed()
        await letItSettle()
        #expect(spy.ids == [aBadge.id])
    }

    @Test("A sheet over a sheet releases only when the last one closes")
    func waitsForTheLastSheet() async {
        let (queue, spy) = make()
        queue.sheetOpened()
        queue.sheetOpened()
        queue.celebrate([aBadge])

        queue.sheetClosed()
        await letItSettle()
        #expect(spy.released.isEmpty)

        queue.sheetClosed()
        await letItSettle()
        #expect(spy.ids == [aBadge.id])
    }

    /// Finishing a tracker can land three at once, and they celebrate
    /// together rather than as three toasts in a row.
    @Test("Several earned behind one sheet arrive together")
    func severalArriveTogether() async {
        let (queue, spy) = make()
        queue.sheetOpened()
        queue.celebrate([aBadge])
        queue.celebrate([another])

        queue.sheetClosed()
        await letItSettle()
        #expect(spy.ids == [aBadge.id, another.id])
    }

    @Test("Closing a sheet with nothing waiting celebrates nothing")
    func nothingWaitingStaysQuiet() async {
        let (queue, spy) = make()
        queue.sheetOpened()
        queue.sheetClosed()
        await letItSettle()
        #expect(spy.released.isEmpty)
    }

    /// Fable, build 40 runtime: a five-badge toast lived and expired under
    /// an alert on both devices. Stopping a session asks "What happened?" in
    /// an alert — the case this queue exists for — and an alert announces
    /// neither its arrival nor its departure.
    @Test("A badge earned under an alert waits for the alert to go")
    func waitsForAnAlert() async {
        let cover = Cover()
        let (queue, spy) = make(cover: cover)
        cover.up = true
        queue.celebrate([aBadge])
        await letItSettle()
        #expect(spy.released.isEmpty)

        cover.up = false          // dismissed; nothing tells the queue
        await letItSettle()
        #expect(spy.ids == [aBadge.id])
    }

    /// A sheet closing over an alert must not release while the alert is
    /// still up.
    @Test("Closing a sheet doesn't release while an alert is still over the root")
    func sheetClosingUnderAnAlertWaits() async {
        let cover = Cover()
        let (queue, spy) = make(cover: cover)
        queue.sheetOpened()
        cover.up = true
        queue.celebrate([aBadge])
        queue.sheetClosed()
        await letItSettle()
        #expect(spy.released.isEmpty)

        cover.up = false
        await letItSettle()
        #expect(spy.ids == [aBadge.id])
    }

    @Test("An empty award is not a celebration")
    func emptyAwardDoesNothing() {
        let (queue, spy) = make()
        queue.celebrate([])
        #expect(spy.released.isEmpty)
    }

    /// `onDisappear` can outnumber `onAppear`. A count driven negative would
    /// read as "nothing is open" and celebrate underneath the next sheet.
    @Test("More closes than opens cannot drive the count below zero")
    func countNeverGoesNegative() async {
        let (queue, spy) = make()
        queue.sheetClosed()
        queue.sheetClosed()
        #expect(queue.openSheets == 0)

        queue.sheetOpened()
        queue.celebrate([aBadge])
        #expect(spy.released.isEmpty)

        queue.sheetClosed()
        await letItSettle()
        #expect(spy.ids == [aBadge.id])
    }
}
