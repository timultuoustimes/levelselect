import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// What the app claims is connected to what.
///
/// The web app called two games similar if they shared ONE tag, which is how
/// The Messenger — Platform, Adventure, Indie, Arcade, Action, Comedy — ended
/// up sitting next to Hogwarts Legacy, Bulletstorm and Mario Odyssey. That
/// isn't a near-miss to tune; sharing one word out of six is not resemblance,
/// and a shelf of obviously-wrong suggestions teaches people to ignore the
/// shelf.
///
/// So the tests here are mostly about what must NOT appear.
@MainActor
struct RelatedGamesTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @discardableResult
    private func game(_ repo: Repository, _ name: String,
                      genres: [String] = [], themes: [String] = [],
                      perspectives: [String] = [], franchise: String? = nil,
                      developers: [String] = [], year: Int? = nil) -> Game {
        let game = repo.addGame(name: name, status: .backlog)
        repo.edit(game) {
            $0.genres = genres
            $0.themes = themes
            $0.playerPerspectives = perspectives
            $0.franchise = franchise
            $0.developers = developers
            if let year {
                $0.firstReleaseDate = Calendar.current.date(
                    from: DateComponents(year: year, month: 1, day: 1))
            }
        }
        return game
    }

    /// Real tags, from the screenshots that prompted this.
    private func messengerLibrary(_ repo: Repository) -> (Game, [Game]) {
        let messenger = game(repo, "The Messenger",
                             genres: ["Platform", "Adventure", "Indie", "Arcade", "Action"],
                             themes: ["Comedy"], perspectives: ["Side view"])
        let hogwarts = game(repo, "Hogwarts Legacy",
                            genres: ["Role-playing (RPG)", "Adventure"],
                            themes: ["Fantasy"], perspectives: ["Third person"])
        let bulletstorm = game(repo, "Bulletstorm",
                               genres: ["Shooter", "Action"],
                               themes: ["Science fiction"], perspectives: ["First person"])
        let odyssey = game(repo, "Super Mario Odyssey",
                           genres: ["Platform", "Adventure"],
                           themes: ["Sandbox"], perspectives: ["Third person"])
        let celeste = game(repo, "Celeste",
                           genres: ["Platform", "Indie", "Adventure"],
                           themes: [], perspectives: ["Side view"])
        return (messenger, [messenger, hogwarts, bulletstorm, odyssey, celeste])
    }

    /// The reported case, exactly.
    @Test func theMessengerIsNotLikeHogwartsLegacyOrBulletstorm() {
        let repo = self.repo()
        let (messenger, library) = messengerLibrary(repo)

        let names = RelatedGames.similar(to: messenger, in: library).map(\.name)

        #expect(!names.contains("Hogwarts Legacy"))
        #expect(!names.contains("Bulletstorm"))
    }

    /// And the thing that IS like it comes back — a rule that excludes
    /// everything is as useless as one that includes everything.
    @Test func aSideOnIndiePlatformerIsSimilar() {
        let repo = self.repo()
        let (messenger, library) = messengerLibrary(repo)

        #expect(RelatedGames.similar(to: messenger, in: library).map(\.name).contains("Celeste"))
    }

    /// One shared tag is never enough. This is the whole bug in one assertion.
    @Test func oneSharedTagIsNotResemblance() {
        let repo = self.repo()
        let a = game(repo, "A", genres: ["Action", "Shooter", "Strategy"], themes: ["Horror"])
        let b = game(repo, "B", genres: ["Action"], themes: ["Comedy", "Fantasy"])

        #expect(RelatedGames.similar(to: a, in: [a, b]).isEmpty)
    }

    /// A game tagged with everything overlaps everything. Two shared tags out
    /// of fifteen is one of them being vague, not the two being alike — so the
    /// ratio has to bite as well as the count.
    @Test func aVaguelyTaggedGameDoesNotMatchEverything() {
        let repo = self.repo()
        let specific = game(repo, "Tight Puzzler",
                            genres: ["Puzzle", "Indie"], perspectives: ["Side view"])
        let everything = game(repo, "Tagged With Everything",
                              genres: ["Puzzle", "Indie", "Action", "Adventure", "Shooter",
                                       "Strategy", "Sport", "Racing", "Fighting", "Platform"],
                              themes: ["Comedy", "Horror", "Fantasy", "Science fiction"],
                              perspectives: ["First person", "Third person"])

        // Two shared tags, but sixteen combined — that is not resemblance.
        #expect(RelatedGames.similar(to: specific, in: [specific, everything]).isEmpty)
    }

    /// Series entries have their own shelf, so repeating them under "plays
    /// like this" would just make that shelf look padded.
    @Test func sameSeriesGamesAreLeftToTheirOwnShelf() {
        let repo = self.repo()
        let one = game(repo, "Sonic the Hedgehog", genres: ["Platform"], themes: ["Action"],
                       perspectives: ["Side view"], franchise: "Sonic")
        let two = game(repo, "Sonic the Hedgehog 2", genres: ["Platform"], themes: ["Action"],
                       perspectives: ["Side view"], franchise: "Sonic")

        #expect(RelatedGames.similar(to: two, in: [one, two]).isEmpty)
        #expect(RelatedGames.sameFranchise(as: two, in: [one, two]).map(\.name)
                == ["Sonic the Hedgehog"])
    }

    /// A game with almost no tags can't be judged, and guessing from one tag
    /// is exactly what this rule exists to stop.
    @Test func aGameWithNoTraitsClaimsNoResemblance() {
        let repo = self.repo()
        let bare = game(repo, "Untagged")
        let rich = game(repo, "Rich", genres: ["Platform", "Indie"], perspectives: ["Side view"])

        #expect(RelatedGames.similar(to: bare, in: [bare, rich]).isEmpty)
    }

    // MARK: Series and studio

    @Test func seriesIsOrderedByRelease() {
        let repo = self.repo()
        let later = game(repo, "Later", franchise: "Series", year: 1994)
        let earlier = game(repo, "Earlier", franchise: "Series", year: 1991)
        let subject = game(repo, "Subject", franchise: "Series", year: 1999)

        #expect(RelatedGames.sameFranchise(as: subject, in: [later, earlier, subject])
                .map(\.name) == ["Earlier", "Later"])
    }

    /// Studio only steps in when there's no series to show, and never repeats
    /// the series it just stood aside for.
    @Test func studioSkipsGamesAlreadyCoveredByTheSeries() {
        let repo = self.repo()
        let subject = game(repo, "Subject", franchise: "Sonic", developers: ["Sega"])
        let sibling = game(repo, "Sonic 3", franchise: "Sonic", developers: ["Sega"])
        let other = game(repo, "Golden Axe", developers: ["Sega"])

        let studio = RelatedGames.sameDeveloper(as: subject, in: [subject, sibling, other])
        #expect(studio?.developer == "Sega")
        #expect(studio?.games.map(\.name) == ["Golden Axe"])
    }

    /// "Comfort games" and "Mega Man X Legacy Collection" are both collections
    /// and they are not the same kind of thing — one is your opinion, the other
    /// is what someone sold you. The model already separates them, and the
    /// game page has to keep them apart rather than flattening both into
    /// "collections you're in".
    @Test func personalListsAndPurchasedBundlesStaySeparate() {
        let repo = self.repo()
        let mm = game(repo, "Mega Man X")

        let comfort = repo.createCollection(name: "Comfort Games")
        repo.setMembership(comfort, game: mm, member: true)
        let legacy = repo.createCollection(name: "Mega Man X Legacy Collection", isBundle: true)
        repo.setMembership(legacy, game: mm, member: true)

        let all = [comfort, legacy]
        let lists = all.filter { $0.contains(mm) && !$0.isBundle }
        let bundles = all.filter { $0.contains(mm) && $0.isBundle }

        #expect(lists.map(\.name) == ["Comfort Games"])
        #expect(bundles.map(\.name) == ["Mega Man X Legacy Collection"])
    }

    @Test func aGameNeverRelatesToItself() {
        let repo = self.repo()
        let solo = game(repo, "Solo", genres: ["Platform", "Indie"],
                        perspectives: ["Side view"], franchise: "Solo Series",
                        developers: ["Studio"])

        #expect(RelatedGames.similar(to: solo, in: [solo]).isEmpty)
        #expect(RelatedGames.sameFranchise(as: solo, in: [solo]).isEmpty)
        #expect(RelatedGames.sameDeveloper(as: solo, in: [solo]) == nil)
    }
}
