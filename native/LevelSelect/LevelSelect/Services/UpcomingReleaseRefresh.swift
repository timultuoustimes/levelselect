import Foundation
import SwiftData

/// Asks IGDB again about games that have not come out yet.
///
/// **The gap this fills.** `MetadataRefresh.plan` looks up a game only when
/// something is *missing* from it, which is right for a library of released
/// games and wrong for a wishlist. A fully-populated upcoming game was never
/// queried again, so its release date stayed frozen at whatever IGDB said the
/// day it was added — and a wishlist is made entirely of games whose dates
/// move. Tim, on two games side by side: *"onimusha way of the sword isn't
/// updating to Today and still says tomorrow, but orbitals, which I just added
/// (literally just added) says today."* Same code, different age.
///
/// It runs where the release reminders already reconcile, and for the reason
/// that reconcile gives: *"a date can move"*. It said so before anything could.
@MainActor
enum UpcomingReleaseRefresh {

    /// Re-ask about anything upcoming that has not been asked about today.
    ///
    /// Returns the games whose date actually changed, so the caller can
    /// reschedule their reminders rather than leave one pointed at a day that
    /// has moved.
    @discardableResult
    static func run(library: [Game], context: ModelContext) async -> [Game] {
        let store = MetadataCheckedStore(key: MetadataCheckedStore.upcomingKey)
        let due = MetadataRefresh.upcomingNeedingRecheck(library, checked: store.all())
        guard !due.isEmpty else { return [] }

        var moved: [Game] = []
        for game in due {
            guard let id = game.igdbID,
                  let igdb = try? await IGDBService.lookup(id: id) else { continue }
            let before = game.effectiveReleaseDate
            // `platformReleases` is what `effectiveReleaseDate` prefers, so it
            // has to travel with the date or the change never surfaces.
            if !igdb.storedPlatformReleases.isEmpty {
                game.platformReleases = igdb.storedPlatformReleases
            }
            if MetadataRefresh.mayMove(game.firstReleaseDate),
               let date = igdb.storableReleaseDate(on: game.chosenPlatform),
               !MetadataRefresh.isYearOnly(date) {
                game.firstReleaseDate = date
            }
            if game.effectiveReleaseDate != before { moved.append(game) }
        }

        // Marked whether or not anything changed: the point of the ledger is
        // "we asked today", not "we got news".
        store.markChecked(due.map(\.id))
        if !moved.isEmpty { try? context.save() }
        return moved
    }
}
