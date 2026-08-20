import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Collection templates, and the drafts some of them start with.
///
/// The seeded ones are the interesting half — they answer their own question
/// from session and ownership data, which is the thing a list app without a
/// timer can't do. So the tests are about the picking rules being *right*,
/// not merely non-empty: a draft that quietly includes the wrong games is
/// worse than no draft, because it looks authoritative.
@MainActor
struct CollectionTemplateTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func game(_ repo: Repository, _ name: String, status: GameStatus = .backlog,
                      ownership: [Ownership] = [], year: Int? = nil,
                      addedAt: Date = .now) -> Game {
        let game = repo.addGame(name: name, status: status)
        repo.edit(game) {
            $0.ownership = ownership.map(\.rawValue)
            $0.addedAt = addedAt
            if let year {
                $0.firstReleaseDate = Calendar.current.date(
                    from: DateComponents(year: year, month: 6, day: 1))
            }
        }
        return game
    }

    /// Log a finished session of `minutes` on a game.
    private func play(_ repo: Repository, _ game: Game, minutes: Int) {
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let start = Date.now.addingTimeInterval(-Double(minutes) * 60)
        let session = repo.startSession(on: pt, at: start)
        repo.stopSession(session, at: .now)
    }

    // MARK: The catalogue itself

    /// Ids are what a collection would ever be traced back to, and duplicates
    /// would make two different prompts indistinguishable.
    @Test func templateIdsAreUnique() {
        let ids = CollectionTemplate.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// A prompt with no number isn't a prompt — the count is the constraint
    /// that makes someone choose.
    @Test func everyTemplateAsksForAWorkableNumber() {
        for template in CollectionTemplate.all {
            #expect(template.slots >= 4, "\(template.id) asks for too few")
            #expect(template.slots <= 12, "\(template.id) asks for too many")
            #expect(!template.prompt.isEmpty)
        }
    }

    /// Grouping drives the whole picker; a template in no group is invisible.
    @Test func everyTemplateIsReachableThroughAGroup() {
        let grouped = CollectionTemplate.grouped().flatMap(\.templates)
        #expect(Set(grouped.map(\.id)) == Set(CollectionTemplate.all.map(\.id)))
    }

    /// The paired opinions read as two sides of one argument, so they have to
    /// stay the same size — a 4 against a 6 makes one look like the main event.
    @Test func pairedOpinionTemplatesAskForTheSameNumber() {
        let pairs = [("original-did-it-better", "better-than-original"),
                     ("preorder-regrets", "worth-paying-early")]
        for (a, b) in pairs {
            let first = CollectionTemplate.all.first { $0.id == a }!
            let second = CollectionTemplate.all.first { $0.id == b }!
            #expect(first.slots == second.slots, "\(a) and \(b) disagree")
            #expect(first.group == second.group)
        }
    }

    /// A prompt about the backlog should open the picker on the backlog. The
    /// link is by name, so it also has to survive being looked up that way.
    @Test func backlogPromptsSayWhereToStartPicking() {
        for id in ["guilt-pile", "longest-held", "lets-be-real", "one-day"] {
            let template = CollectionTemplate.all.first { $0.id == id }!
            #expect(template.picksFrom == .backlog, "\(id) should start on the backlog")
            #expect(CollectionTemplate.matching(collectionNamed: template.name)?.id == id)
        }
        #expect(CollectionTemplate.all.first { $0.id == "still-waiting" }?.picksFrom == .wishlist)
    }

    /// Matching is forgiving about case and punctuation but must not match
    /// something else entirely — a wrong match would open the picker filtered
    /// to a status the user never asked for.
    @Test func collectionNameMatchingIsLooseButNotWrong() {
        #expect(CollectionTemplate.matching(collectionNamed: "let's be real")?.id == "lets-be-real")
        #expect(CollectionTemplate.matching(collectionNamed: "Lets Be Real")?.id == "lets-be-real")
        #expect(CollectionTemplate.matching(collectionNamed: "My Own List") == nil)
        #expect(CollectionTemplate.matching(collectionNamed: "") == nil)
    }

    /// The tally reads the slot count back off the collection's name, so a
    /// collection made from a prompt has to keep resolving to it — otherwise
    /// "pick six" is displayed while choosing and then never counted.
    @Test func aCreatedCollectionStillResolvesToItsTemplateForTheTally() {
        let repo = self.repo()
        for template in CollectionTemplate.all {
            let collection = repo.createCollection(from: template)
            let found = CollectionTemplate.matching(collectionNamed: collection.name)
            #expect(found?.id == template.id, "\(template.id) lost its link")
            #expect(found?.slots == template.slots)
        }
    }

    // MARK: Creating

    @Test func creatingFromATemplateKeepsTheQuestion() {
        let repo = self.repo()
        let template = CollectionTemplate.all.first { $0.id == "the-shelf" }!

        let collection = repo.createCollection(from: template)

        #expect(collection.name == "The Shelf")
        // The prompt survives creation, or a month later it's a list with a
        // cryptic name and no stated rule.
        #expect(collection.notes.contains("keep only nine"))
        #expect(collection.notes.contains("9"))
        #expect(collection.gameIDs.isEmpty)
    }

    @Test func aSeededTemplateArrivesWithGamesInIt() {
        let repo = self.repo()
        let a = game(repo, "Hades"); play(repo, a, minutes: 600)
        let b = game(repo, "Celeste"); play(repo, b, minutes: 60)
        _ = game(repo, "Never Played")

        let template = CollectionTemplate.all.first { $0.id == "hundred-hours" }!
        let picks = CollectionSeeding.games(for: template.seed!, from: [a, b],
                                            limit: template.slots)
        let collection = repo.createCollection(from: template, seededWith: picks)

        #expect(collection.gameIDs == [a.id.uuidString, b.id.uuidString])
    }

    /// The opt-out path. Passing no seed has to produce a genuinely empty
    /// list, not a quietly re-seeded one — "Let's Be Real" answered for you
    /// isn't a confession, and the toggle would be a lie.
    @Test func aTemplateCanBeStartedEmptyEvenWhenItCouldSuggest() {
        let repo = self.repo()
        let old = Date.now.addingTimeInterval(-400 * 86_400)
        _ = game(repo, "Never Opened", status: .backlog, addedAt: old)

        let template = CollectionTemplate.all.first { $0.id == "lets-be-real" }!
        #expect(template.seed != nil)   // it CAN suggest…

        let collection = repo.createCollection(from: template)   // …and wasn't asked to
        #expect(collection.gameIDs.isEmpty)
        #expect(collection.notes.contains("aren't getting opened"))
    }

    // MARK: The picking rules

    /// Most played first, and a game with no time at all is not an answer to
    /// "where has your time gone".
    @Test func mostPlayedRanksByTimeAndSkipsUnplayedGames() {
        let repo = self.repo()
        let big = game(repo, "Big"); play(repo, big, minutes: 900)
        let small = game(repo, "Small"); play(repo, small, minutes: 30)
        let none = game(repo, "Untouched")

        let picked = CollectionSeeding.games(for: .mostPlayed,
                                             from: [small, none, big], limit: 6)
        #expect(picked.map(\.name) == ["Big", "Small"])
    }

    /// "One sitting" means one session AND a finish. Two sessions means you
    /// got up, which is the entire claim the prompt makes.
    @Test func oneSittingNeedsBothASingleSessionAndAFinish() {
        let repo = self.repo()

        let clean = game(repo, "Clean Run")
        play(repo, clean, minutes: 200)
        repo.addCompletion(to: clean)

        let interrupted = game(repo, "Two Nights")
        play(repo, interrupted, minutes: 100)
        play(repo, interrupted, minutes: 100)
        repo.addCompletion(to: interrupted)

        let unfinished = game(repo, "Still Going")
        play(repo, unfinished, minutes: 200)

        let picked = CollectionSeeding.games(
            for: .singleSitting, from: [clean, interrupted, unfinished], limit: 4)
        #expect(picked.map(\.name) == ["Clean Run"])
    }

    /// "Cartridge shelf" is retro AND physical. Physical alone would return a
    /// shelf of last year's Switch games, which is not the prompt.
    @Test func cartridgeShelfIsRetroAndPhysicalNotEither() {
        let repo = self.repo()
        let old = game(repo, "Castlevania", ownership: [.physical], year: 1986)
        let modern = game(repo, "New Physical", ownership: [.physical], year: 2024)
        let oldDigital = game(repo, "Old Digital", ownership: [.digital], year: 1990)

        let picked = CollectionSeeding.games(for: .physicalRetro,
                                             from: [modern, oldDigital, old], limit: 9)
        #expect(picked.map(\.name) == ["Castlevania"])
    }

    /// "You'll never hold a copy" — so a game you ALSO own physically doesn't
    /// belong, even though it is emulated too.
    @Test func emulatedOnlyExcludesGamesYouAlsoOwnForReal() {
        let repo = self.repo()
        let pure = game(repo, "Emulated", ownership: [.emulated])
        let both = game(repo, "Both", ownership: [.emulated, .physical])

        let picked = CollectionSeeding.games(for: .emulatedOnly, from: [both, pure], limit: 6)
        #expect(picked.map(\.name) == ["Emulated"])
    }

    /// Newest additions first: the ones you meant to play are the ones you
    /// added while meaning to play them.
    @Test func theGuiltPileLeadsWithWhatYouAddedMostRecently() {
        let repo = self.repo()
        let old = game(repo, "Old Add", status: .backlog,
                       addedAt: .now.addingTimeInterval(-90 * 86_400))
        let fresh = game(repo, "Fresh Add", status: .backlog,
                         addedAt: .now.addingTimeInterval(-86_400))
        let playing = game(repo, "Playing Now", status: .playing)

        let picked = CollectionSeeding.games(for: .backlog,
                                             from: [old, playing, fresh], limit: 6)
        #expect(picked.map(\.name) == ["Fresh Add", "Old Add"])
    }

    /// Wishlist and not out yet — a released wishlist game is something you
    /// haven't bought, not something you're waiting for.
    @Test func stillWaitingMeansUnreleased() {
        let repo = self.repo()
        let upcoming = game(repo, "GTA VI", status: .wishlist, year: 2030)
        let released = game(repo, "Out Already", status: .wishlist, year: 2020)
        let unknown = game(repo, "No Date", status: .wishlist)
        let owned = game(repo, "Owned Upcoming", status: .backlog, year: 2030)

        let picked = CollectionSeeding.games(
            for: .unreleasedWishlist, from: [released, owned, upcoming, unknown], limit: 4)
        #expect(Set(picked.map(\.name)) == ["GTA VI", "No Date"])
    }

    /// The mirror of The Guilt Pile: same shelf, opposite end. If these two
    /// ever return the same order, one of them has stopped saying anything.
    @Test func longestHeldIsTheOppositeEndOfTheShelfFromTheGuiltPile() {
        let repo = self.repo()
        let ancient = game(repo, "Ancient", status: .backlog,
                           addedAt: .now.addingTimeInterval(-900 * 86_400))
        let recent = game(repo, "Recent", status: .backlog,
                          addedAt: .now.addingTimeInterval(-2 * 86_400))

        let oldest = CollectionSeeding.games(for: .longestHeld, from: [recent, ancient], limit: 6)
        let newest = CollectionSeeding.games(for: .backlog, from: [recent, ancient], limit: 6)
        #expect(oldest.map(\.name) == ["Ancient", "Recent"])
        #expect(newest.map(\.name) == ["Recent", "Ancient"])
    }

    /// "Never once started" is a stronger admission than "unfinished" — a game
    /// played for an hour and put down does not belong here, and including it
    /// would make the list a lie rather than a confession.
    @Test func letsBeRealNeedsOldAndCompletelyUntouched() {
        let repo = self.repo()
        let old = Date.now.addingTimeInterval(-400 * 86_400)

        let untouched = game(repo, "Never Opened", status: .backlog, addedAt: old)
        let dabbled = game(repo, "Played An Hour", status: .backlog, addedAt: old)
        play(repo, dabbled, minutes: 60)
        let recent = game(repo, "Bought Last Week", status: .backlog,
                          addedAt: .now.addingTimeInterval(-7 * 86_400))
        let finished = game(repo, "Finished", status: .completed, addedAt: old)

        let picked = CollectionSeeding.games(
            for: .neverStarted, from: [dabbled, recent, finished, untouched], limit: 6)
        #expect(picked.map(\.name) == ["Never Opened"])
        // The draft is where the answer usually lives, but which of these is
        // never getting opened is a judgement — so the prompt says so rather
        // than reading like the query behind it.
        let template = CollectionTemplate.all.first { $0.id == "lets-be-real" }!
        #expect(template.prompt.lowercased().contains("years"))
        #expect(!template.prompt.contains("Never once started"))
    }

    /// Never more than the template asks for — the count is the point.
    @Test func aDraftNeverExceedsTheSlotCount() {
        let repo = self.repo()
        let games = (1...10).map { index -> Game in
            let g = game(repo, "Game \(index)", status: .backlog)
            play(repo, g, minutes: index * 10)
            return g
        }
        #expect(CollectionSeeding.games(for: .mostPlayed, from: games, limit: 6).count == 6)
        #expect(CollectionSeeding.games(for: .backlog, from: games, limit: 6).count == 6)
    }
}
