import Testing
import Foundation
@testable import LevelSelect

/// Home is a self-portrait; this pins the grammar that stores it.
struct HomeLayoutTests {

    @Test("Nothing stored gives the default: continue, the case, then Home's shelves")
    func defaultComposition() {
        let layout = HomeLayout.resolve(raw: nil)
        #expect(layout.visibleBlocks.prefix(3) == [.continuePlaying, .systems, .status(.playing)])
        #expect(layout.systemsCount == 6)
        #expect(layout.systemsStyle == .grid)
        #expect(layout.isHidden(.collections))
        #expect(layout.isHidden(.status(.backlog)))
        #expect(!layout.isHidden(.status(.queued)))
    }

    @Test("The device-local hidden set is honored only until something is stored")
    func legacyHiddenStatuses() {
        let fresh = HomeLayout.resolve(raw: nil, legacyHiddenStatuses: [.paused])
        #expect(fresh.isHidden(.status(.paused)))
        let stored = HomeLayout.resolve(raw: fresh.raw, legacyHiddenStatuses: [.queued])
        #expect(!stored.isHidden(.status(.queued)))
        #expect(stored.isHidden(.status(.paused)))
    }

    @Test("Round trip keeps order, hidden flags, and the systems count and style")
    func roundTrip() {
        var layout = HomeLayout.standard
        layout.systemsCount = 9
        layout.systemsStyle = .row
        layout.setHidden(.status(.paused), true)
        let id = UUID()
        layout.pin(collection: id)
        layout.move(fromOffsets: IndexSet(integer: layout.entries.count - 1), toOffset: 2)

        let back = HomeLayout.resolve(raw: layout.raw)
        #expect(back == layout)
        #expect(back.visibleBlocks[2] == .collection(id))
        #expect(back.raw.contains("systems:9:row"))
        #expect(back.raw.contains("-status:paused"))
    }

    @Test("Unknown tokens are dropped and missing defaults slot back in beside their neighbours")
    func forgivingParse() {
        let layout = HomeLayout.resolve(raw: "status:playing,widgets:3,continue,-status:queued")
        #expect(layout.visibleBlocks.first == .status(.playing))
        #expect(layout.entries.contains { $0.block == .systems })
        #expect(layout.isHidden(.status(.queued)))
        #expect(layout.isHidden(.collections))
        // The wishlist is a tab, never a shelf here.
        #expect(!HomeLayout.resolve(raw: "status:wishlist").entries.contains { $0.block == .status(.wishlist) })
    }

    @Test("A systems count outside the range falls back rather than storing nonsense")
    func countRange() {
        #expect(HomeLayout.resolve(raw: "systems:0:grid").systemsCount == 6)
        #expect(HomeLayout.resolve(raw: "systems:40").systemsCount == 6)
        #expect(HomeLayout.resolve(raw: "systems:3").systemsCount == 3)
    }

    @Test("Unpinning removes the block; pinning twice does not duplicate it")
    func pinUnpin() {
        var layout = HomeLayout.standard
        let id = UUID()
        layout.pin(collection: id)
        layout.pin(collection: id)
        #expect(layout.pinnedCollections == [id])
        layout.unpin(collection: id)
        #expect(layout.pinnedCollections.isEmpty)
    }
}

struct HomeSystemsTests {
    private let snes = "Super Nintendo Entertainment System"
    private let genesis = "Sega Mega Drive/Genesis"
    private let sw = "Nintendo Switch"
    private let ps5 = "PlayStation 5"

    private var groups: [HomeSystems.Group] {
        [(sw, 44), (snes, 31), (ps5, 22), (genesis, 18)]
    }

    @Test("Nothing stored: most games first")
    func defaultOrder() {
        #expect(HomeSystems.ordered(raw: nil, available: groups).map(\.platform) == [sw, snes, ps5, genesis])
    }

    @Test("A stored order wins, and a newcomer lands at the end")
    func storedOrderThenNewcomers() {
        let raw = HomeSystems.raw(order: [snes, genesis], sort: .custom)
        let out = HomeSystems.ordered(raw: raw, available: groups).map(\.platform)
        #expect(out == [snes, genesis, sw, ps5])
    }

    @Test("A stored system no longer in the library is simply absent")
    func staleEntriesVanish() {
        let raw = HomeSystems.raw(order: ["Atari Jaguar", snes], sort: .custom)
        #expect(HomeSystems.ordered(raw: raw, available: groups).first?.platform == snes)
    }

    @Test("Release order is North American initial release, unknowns last")
    func releaseOrder() {
        let out = HomeSystems.sorted(groups + [("Other", 3)], by: .release).map(\.platform)
        #expect(out == [genesis, snes, sw, ps5, "Other"])
    }

    @Test("The sort token round-trips")
    func sortToken() {
        let raw = HomeSystems.raw(order: [snes], sort: .release)
        #expect(HomeSystems.parse(raw).sort == .release)
        #expect(HomeSystems.parse(raw).order == [snes])
        #expect(HomeSystems.parse("sort=nonsense,X").sort == .custom)
    }
}
