import Testing
import Foundation
@testable import LevelSelect

/// **The parts of the Wikidata integration that are worth pinning without a
/// network.**
///
/// Not the request — that is one URLSession call and a decode, and a test of
/// it would only assert that Foundation works. What matters is the shaping and
/// the rules: credits read in a sensible order, a disagreement is a question
/// rather than a correction, and the year comparison does not cry wolf over a
/// regional release date.
@MainActor
struct WikidataServiceTests {

    private func entry(released: String? = nil,
                       credits: [WikidataService.Credit] = []) -> WikidataService.Entry {
        WikidataService.Entry(qid: "Q29300592", title: "Hollow Knight",
                              series: nil, released: released, credits: credits)
    }

    // MARK: Credits

    @Test func aRoleReadsAsAWord() {
        #expect(WikidataService.Credit(role: "director", name: "A").label == "Director")
        #expect(WikidataService.Credit(role: "composer", name: "A").label == "Composer")
        #expect(WikidataService.Credit(role: "designer", name: "A").label == "Designer")
        #expect(WikidataService.Credit(role: "writer", name: "A").label == "Writer")
        // A property we did not name still reads as something, rather than as
        // a raw query binding.
        #expect(WikidataService.Credit(role: "producer", name: "A").label == "Producer")
    }

    /// Query order is arbitrary; a credits list is read top to bottom.
    @Test func creditsReadInAStableOrder() {
        let e = entry(credits: [
            .init(role: "composer", name: "Christopher Larkin"),
            .init(role: "writer", name: "Zed"),
            .init(role: "director", name: "Ari Gibson"),
            .init(role: "designer", name: "William Pellen"),
        ])
        #expect(e.orderedCredits.map(\.role) == ["director", "designer", "writer", "composer"])
    }

    @Test func twoPeopleInOneRoleSortByName() {
        let e = entry(credits: [
            .init(role: "director", name: "Zoe"),
            .init(role: "director", name: "Ari"),
        ])
        #expect(e.orderedCredits.map(\.name) == ["Ari", "Zoe"])
    }

    // MARK: Cross-checking, which never corrects

    @Test func aDifferentYearIsReported() {
        let stored = Calendar.current.date(from: DateComponents(year: 2017, month: 2, day: 24))!
        let found = WikidataService.releaseYearDisagreement(entry(released: "2018-01-01T00:00:00Z"),
                                                            storedFirstRelease: stored)
        #expect(found?.wikidata == 2018)
        #expect(found?.stored == 2017)
    }

    /// **Compared at year granularity on purpose.** A regional release a month
    /// apart is not a discrepancy worth putting in front of anybody, and an
    /// integration that cries wolf gets ignored when it is right.
    @Test func aDifferentMonthInTheSameYearIsNotADisagreement() {
        let stored = Calendar.current.date(from: DateComponents(year: 2017, month: 2, day: 24))!
        #expect(WikidataService.releaseYearDisagreement(entry(released: "2017-11-30T00:00:00Z"),
                                                        storedFirstRelease: stored) == nil)
    }

    @Test func nothingToCompareIsNotADisagreement() {
        let stored = Calendar.current.date(from: DateComponents(year: 2017, month: 2, day: 24))!
        // No Wikidata date…
        #expect(WikidataService.releaseYearDisagreement(entry(), storedFirstRelease: stored) == nil)
        // …and no stored date.
        #expect(WikidataService.releaseYearDisagreement(entry(released: "2018-01-01T00:00:00Z"),
                                                        storedFirstRelease: nil) == nil)
    }

    /// A malformed date says nothing rather than reporting year zero.
    @Test func anUnparseableDateSaysNothing() {
        let stored = Calendar.current.date(from: DateComponents(year: 2017, month: 2, day: 24))!
        #expect(WikidataService.releaseYearDisagreement(entry(released: "unknown"),
                                                        storedFirstRelease: stored) == nil)
    }

    // MARK: The field it hangs off

    /// IGDB stays the identity source: this is enrichment pointed at a slug,
    /// and the QID is stored so the lookup is not repeated.
    @Test func theQidIsWhatAGameRemembers() {
        let game = Game(name: "Hollow Knight")
        game.igdbSlug = "hollow-knight"
        #expect(game.wikidataID == nil)
        game.wikidataID = entry().qid
        #expect(game.wikidataID == "Q29300592")
        // And the slug — the bridge — is untouched by any of it.
        #expect(game.igdbSlug == "hollow-knight")
    }
}
