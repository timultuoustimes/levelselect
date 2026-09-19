import Testing
import Foundation
import SwiftUI
@testable import LevelSelect

/// The app's models against what the site actually serves.
///
/// These two feeds are the one place LevelSelect reads a shape it doesn't
/// own — `site/src/pages/changelog/feed.json.ts` and `roadmap/feed.json.ts`
/// build them from the same content that builds the pages. That's the point,
/// and it's also the risk: a field renamed on the site is a What's New screen
/// that says "couldn't reach levelselect.app" on every device, with nothing in
/// the app to blame.
///
/// The fixtures below are real output, copied from those endpoints and trimmed
/// for length. If a change to the site breaks these, it breaks them here first.
struct NewsFeedTests {

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Changelog

    @Test func theChangelogDecodesAsServed() throws {
        let feed = try decode(Self.changelogJSON, as: NewsFeeds.Changelog.self)
        #expect(feed.releases.count == 2)
        let latest = try #require(feed.releases.first)
        #expect(latest.build == 36)
        #expect(!latest.title.isEmpty)
        #expect(!latest.summary.isEmpty)
        #expect(!latest.items.isEmpty)
        #expect(latest.url != nil)
    }

    /// Each item is a heading and its first paragraph, parsed server-side so
    /// the app needs no markdown renderer.
    @Test func itemsCarryATitleAndADetail() throws {
        let feed = try decode(Self.changelogJSON, as: NewsFeeds.Changelog.self)
        for release in feed.releases {
            for item in release.items {
                #expect(!item.title.isEmpty)
                #expect(!item.title.contains("["),
                        Comment(rawValue: "the [tag] suffix should be stripped: \(item.title)"))
            }
        }
    }

    /// A tag the site adds later must not blank the screen on an app that
    /// shipped before it.
    @Test func anUnknownKindDecodesAsNew() throws {
        let json = """
        {"releases":[{"id":"x","version":"1","build":1,"date":"2026-01-01T00:00:00.000Z",
        "title":"t","summary":"s","items":[{"title":"i","kind":"rearranged","detail":"d"}]}]}
        """
        let feed = try decode(json, as: NewsFeeds.Changelog.self)
        #expect(feed.releases[0].items[0].kind == .new)
    }

    /// `0.1.0-beta` has no build number, and the app must not choke on it.
    @Test func aReleaseWithoutABuildNumberStillDecodes() throws {
        let json = """
        {"releases":[{"id":"010-beta","version":"beta","build":null,
        "date":"2026-01-01T00:00:00.000Z","title":"t","summary":"s","items":[]}]}
        """
        let feed = try decode(json, as: NewsFeeds.Changelog.self)
        #expect(feed.releases[0].build == nil)
    }

    // MARK: Roadmap

    @Test func theRoadmapDecodesAsServed() throws {
        let feed = try decode(Self.roadmapJSON, as: NewsFeeds.Roadmap.self)
        #expect(feed.horizons.map(\.name) == ["Now", "Next", "Exploring"])
        #expect(!feed.reviewed.isEmpty)
        #expect(!feed.disclaimer.isEmpty)
        #expect(!feed.notPlanned.isEmpty)
    }

    /// The dots beside Now / Next / Exploring are the site's own colors, and
    /// `Color(hex:)` has to accept them as written.
    @Test func everyHorizonColourParses() throws {
        let feed = try decode(Self.roadmapJSON, as: NewsFeeds.Roadmap.self)
        for horizon in feed.horizons {
            #expect(Color(hex: horizon.color) != nil,
                    Comment(rawValue: "unparseable horizon color: \(horizon.color)"))
        }
    }

    /// Accounts, ads, analytics and tracking are stated as not-planned on the
    /// site. The app repeats it, so the app has to be able to read it.
    @Test func whatIsNotPlannedComesThroughIntact() throws {
        let feed = try decode(Self.roadmapJSON, as: NewsFeeds.Roadmap.self)
        for entry in feed.notPlanned {
            #expect(!entry.title.isEmpty)
            #expect(!entry.detail.isEmpty)
        }
    }

    // MARK: Fixtures — real output, trimmed

    static let changelogJSON = """
{
  "generated": "2026-09-05T23:11:50.267Z",
  "releases": [
    {
      "id": "010-36",
      "version": "0.1.0 (36)",
      "build": 36,
      "date": "2026-09-03T00:00:00.000Z",
      "title": "The part that already happened",
      "summary": "The Stats tab becomes the Journal \\u2014 everything you've written down, in order, with room for the thirty years that happened before you installed this. And the whole app can be light now, in whatever color you like.",
      "items": [
        {
          "title": "Everything you've written, in order",
          "kind": "new",
          "detail": "The timeline is built from what was already there. Nothing new had to be stored to show it."
        },
        {
          "title": "Things that happened before you had this",
          "kind": "new",
          "detail": "The app could only hold what it watched. Your library starts the day you installed it, and the part of your gaming life worth writing down mostly doesn't."
        }
      ],
      "url": "https://levelselect.app/changelog/#build-36"
    },
    {
      "id": "010-35",
      "version": "0.1.0 (35)",
      "build": 35,
      "date": "2026-09-02T00:00:00.000Z",
      "title": "When it lands, and which one is yours",
      "summary": "Stats says what it is, a game you're waiting for tells you when it arrives \\u2014 on your platform, not somebody else's \\u2014 and a date bug that had been quietly wrong for months got found.",
      "items": [
        {
          "title": "Stats is your history, in three questions",
          "kind": "new",
          "detail": "Fourteen cards in one scroll read as fourteen charts. They're grouped now by the question each answers:"
        },
        {
          "title": "A game you're waiting for tells you when",
          "kind": "new",
          "detail": "Four things, and they all count to the same day:"
        }
      ],
      "url": "https://levelselect.app/changelog/#build-35"
    }
  ]
}

"""

    static let roadmapJSON = """
{
  "generated": "2026-09-05T23:11:50.307Z",
  "reviewed": "3 September 2026",
  "disclaimer": "A direction, not a set of promises.",
  "horizons": [
    {
      "key": "now",
      "name": "Now",
      "note": "being worked on",
      "color": "#30D158",
      "items": [
        {
          "title": "Settling the beta",
          "detail": "Making the things people use every day dependable before adding more."
        }
      ]
    },
    {
      "key": "next",
      "name": "Next",
      "note": "planned",
      "color": "#0A84FF",
      "items": [
        {
          "title": "The consoles themselves",
          "detail": "A system becomes something you own in its own right, with add-ons attached to the machine they plug into \\u2014 rather than a label that only ever exists on a game."
        }
      ]
    },
    {
      "key": "exploring",
      "name": "Exploring",
      "note": "no commitment",
      "color": "#BF5AF2",
      "items": [
        {
          "title": "Badges",
          "detail": "Recognition for what you've actually done, earned once and kept."
        }
      ]
    }
  ],
  "shipped": [
    {
      "title": "The Journal",
      "detail": "Everything you have written down, in order. A day of a game is one entry, not three, and it asks what happened while it is still what you were just doing.",
      "build": 36,
      "url": "https://levelselect.app/changelog/#build-36"
    },
    {
      "title": "The part that happened before the app",
      "detail": "Memories, dated as vaguely as you actually remember them \\u2014 an exact day, a month, a year, or \\"Christmas 1995 or 1996\\" in your own words. Pictures included.",
      "build": 36,
      "url": "https://levelselect.app/changelog/#build-36"
    }
  ],
  "notPlanned": [
    {
      "title": "Accounts",
      "detail": "Your library lives in your own iCloud. There's nothing to sign up for."
    },
    {
      "title": "Ads, analytics or tracking",
      "detail": "Not now, not later."
    },
    {
      "title": "A social network",
      "detail": "Sharing something you choose to share is one thing; a feed is another."
    }
  ]
}
"""
}
