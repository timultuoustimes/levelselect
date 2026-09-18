import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The news reader: parsing, finding feeds, importing OPML, matching stories
/// to topics and games, laying out All, and the store writes behind it.
struct FeedParserTests {
    let feedID = UUID()

    @Test func rssWithMediaContentAndCategories() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel><title>Nintendo Life | Latest</title><link>https://www.nintendolife.com</link>
        <item>
          <title>Metroid Ravenous gets a January date &amp; a Special Edition</title>
          <link>https://www.nintendolife.com/news/1</link>
          <guid isPermaLink="false">nl-1</guid>
          <pubDate>Thu, 17 Sep 2026 17:00:00 GMT</pubDate>
          <description><![CDATA[<p>Nintendo confirmed it <b>today</b>.</p>]]></description>
          <category>Nintendo Switch 2</category>
          <media:content url="https://images.nl/1.jpg" type="image/jpeg" medium="image"/>
          <media:thumbnail url="https://images.nl/1-small.jpg"/>
        </item>
        </channel></rss>
        """
        let feed = try #require(FeedParser.parse(Data(xml.utf8), feedID: feedID))
        #expect(feed.title == "Nintendo Life | Latest")
        #expect(feed.siteURL?.absoluteString == "https://www.nintendolife.com")
        let story = try #require(feed.stories.first)
        #expect(story.title == "Metroid Ravenous gets a January date & a Special Edition")
        #expect(story.guid == "nl-1")
        #expect(story.imageURL?.absoluteString == "https://images.nl/1.jpg")
        #expect(story.summary == "Nintendo confirmed it today.")
        #expect(story.categories == ["Nintendo Switch 2"])
        #expect(story.published == Date(timeIntervalSince1970: 1_789_664_400))
    }

    @Test func atomWithAlternateLinkAndImageInContent() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>RPG Site</title>
          <link rel="alternate" href="https://www.rpgsite.net"/>
          <entry>
            <title>Trails anniversary stream announced</title>
            <link rel="alternate" href="https://www.rpgsite.net/news/9"/>
            <id>tag:rpgsite.net,2026:9</id>
            <updated>2026-09-17T23:27:00Z</updated>
            <content type="html">&lt;img src="/img/9.jpg"&gt;&lt;p&gt;Falcom&amp;#8217;s stream&lt;/p&gt;</content>
          </entry>
        </feed>
        """
        let feed = try #require(FeedParser.parse(Data(xml.utf8), feedID: feedID))
        let story = try #require(feed.stories.first)
        #expect(story.link?.absoluteString == "https://www.rpgsite.net/news/9")
        #expect(story.guid == "tag:rpgsite.net,2026:9")
        #expect(story.imageURL?.absoluteString == "https://www.rpgsite.net/img/9.jpg")
        #expect(story.summary == "Falcom’s stream")
        #expect(story.published != nil)
    }

    @Test func noGuidFallsBackToLinkAndNoImageIsFine() throws {
        let xml = """
        <rss><channel><title>HG101</title>
        <item><title>A long retrospective</title><link>https://hg101.net/a</link>
        <pubDate>Sun, 13 Sep 2026 19:24:51 +0000</pubDate></item></channel></rss>
        """
        let story = try #require(FeedParser.parse(Data(xml.utf8), feedID: feedID)?.stories.first)
        #expect(story.guid == "https://hg101.net/a")
        #expect(story.imageURL == nil)
        #expect(story.summary == nil)
    }

    @Test func aWebPageIsNotAFeed() {
        let html = "<!doctype html><html><head><title>Hi</title></head><body><p>nope</p></body></html>"
        #expect(FeedParser.parse(Data(html.utf8), feedID: feedID) == nil)
    }

    @Test func rfc822WithZoneAbbreviation() {
        #expect(FeedParser.date("Thu, 17 Sep 2026 09:38:00 CDT") != nil)
        #expect(FeedParser.date("2026-09-17T08:12:42-04:00") != nil)
    }

    @Test func trackingPixelsAreNotStoryImages() {
        let html = #"<img src="https://feeds.feedburner.com/~r/x.gif"><img src="https://site/a.jpg">"#
        #expect(FeedParser.firstImage(inHTML: html, base: nil)?.absoluteString == "https://site/a.jpg")
    }

    @Test func longSummariesStopAtASentence() {
        let long = String(repeating: "Word word word word. ", count: 30)
        let cut = FeedParser.plainText(long)
        #expect(cut.count <= 241)
        #expect(cut.hasSuffix("."))
    }
}

struct FeedDiscoveryTests {
    @Test func findsTheAdvertisedFeedButNotComments() {
        let html = """
        <head>
        <link rel="alternate" type="application/rss+xml" title="Comments" href="/comments/feed/">
        <link rel="alternate" type="application/rss+xml" title="Retro Dodo" href="/feed/">
        </head>
        """
        let base = URL(string: "https://retrododo.com/")!
        #expect(FeedDiscovery.feedLinks(inHTML: html, base: base).map(\.absoluteString) == ["https://retrododo.com/feed/"])
    }

    @Test func typedAddressesBecomeURLs() {
        #expect(FeedDiscovery.normalized("nintendolife.com")?.absoluteString == "https://nintendolife.com")
        #expect(FeedDiscovery.normalized("feed://example.com/rss")?.absoluteString == "https://example.com/rss")
        #expect(FeedDiscovery.normalized("not a url") == nil)
    }

    @Test func spellingsOfOneFeedShareAKey() {
        #expect(FeedDiscovery.key("https://www.nintendolife.com/feeds/latest/")
                == FeedDiscovery.key("http://nintendolife.com/feeds/latest"))
    }
}

struct OPMLTests {
    /// The shape of Tim's Inoreader export: loose feeds, folders, and
    /// Inoreader's own `@ino.to` entries.
    @Test func foldersAreKeptAndInoreaderOwnEntriesAreUnfetchable() {
        let opml = """
        <opml version="1.0"><body>
          <outline text="The New Yorker" type="rss" xmlUrl="https://www.newyorker.com/feed/rss" htmlUrl="https://www.newyorker.com"/>
          <outline text="the mix" type="rss" xmlUrl="themix@ino.to"/>
          <outline text="Gaming" title="Gaming">
            <outline text="Game Informer" type="rss" xmlUrl="https://www.gameinformer.com/rss.xml" htmlUrl="https://www.gameinformer.com"/>
            <outline text="Time Extension" type="rss" xmlUrl="https://www.timeextension.com/feed"/>
          </outline>
          <outline text="Nature &amp; Gardening" title="Nature &amp; Gardening">
            <outline text="Grow Native!" type="rss" xmlUrl="https://grownative.org/feed/"/>
          </outline>
        </body></opml>
        """
        let entries = OPMLParser.parse(Data(opml.utf8))
        #expect(entries.count == 5)
        #expect(entries.filter { $0.folder == "Gaming" }.map(\.title) == ["Game Informer", "Time Extension"])
        #expect(entries.first { $0.title == "Grow Native!" }?.folder == "Nature & Gardening")
        #expect(entries.first { $0.title == "The New Yorker" }?.folder == nil)
        #expect(entries.filter { !$0.isFetchable }.map(\.title) == ["the mix"])
    }
}

struct FeedCatalogTests {
    @Test func sevenStartOnOneFeedPerAddress() {
        #expect(FeedCatalog.startsOn.count == 7)
        let keys = FeedCatalog.all.map { FeedDiscovery.key($0.feedURL) }
        #expect(Set(keys).count == keys.count)
        #expect(FeedCatalog.all.allSatisfy { URL(string: $0.feedURL)?.scheme?.hasPrefix("http") == true })
    }

    @Test func everyStarterGroupIsCoveredOnce() {
        let groups = FeedCatalog.startsOn.map(\.group)
        for g in [FeedCatalog.Group.nintendo, .playstation, .xbox, .pc, .retro] {
            #expect(groups.filter { $0 == g }.count == 1)
        }
    }
}

struct NewsTopicTests {
    private func story(_ title: String, categories: [String] = []) -> FeedStory {
        FeedStory(guid: title, feedID: UUID(), title: title, link: nil, published: .now,
                  summary: nil, imageURL: nil, categories: categories)
    }

    @Test func headlinesAndCategoriesMatchOnWholeWords() {
        #expect(NewsTopic.playstation.matches(story("PS5 Pro sales pass 5 million"), group: nil))
        #expect(!NewsTopic.pc.matches(story("Epic PCB teardown"), group: nil))
        #expect(NewsTopic.mac.matches(story("Cyberpunk 2077 is out on Mac today"), group: nil))
        #expect(!NewsTopic.mac.matches(story("Machine Girl soundtrack returns"), group: nil))
        #expect(NewsTopic.retro.matches(story("A new Game Boy emulator"), group: nil))
        #expect(NewsTopic.reviews.matches(story("Hades II", categories: ["Reviews"]), group: nil))
        #expect(NewsTopic.reviews.matches(story("iBuyPower RDY Scale B06 review"), group: nil))
        #expect(NewsTopic.reviews.matches(story("Hades II review: the rare sequel that earns its scope"), group: nil))
        #expect(NewsTopic.reviews.matches(story("Mini Review: Kirby Air Riders"), group: nil))
        // Seen live on 09-17: a shop story, not a review.
        #expect(!NewsTopic.reviews.matches(
            story("Pokémon Trading Card Store Denies Giving Special Treatment to Celebrities, as Angry Customers Leave a Flood of Negative Reviews"),
            group: nil))
        #expect(NewsTopic.previews.matches(story("Ghost of Yotei hands-on: a quieter samurai"), group: nil))
    }

    @Test func aCatalogFeedLendsItsGroup() {
        #expect(NewsTopic.xbox.matches(story("A weekend of patches"), group: .xbox))
    }

    @Test func genesisIsNotNintendo() {
        let owned = NewsTopic.owned(platforms: ["Sega Genesis"])
        #expect(!owned.contains(.nintendo))
        #expect(owned.contains(.retro))
    }

    @Test func yourSystemsComeFirstAfterReviews() {
        let order = NewsTopic.ordered(owned: [.xbox, .mac])
        #expect(Array(order.prefix(3)) == [.reviews, .xbox, .mac])
    }
}

struct GameNewsMatcherTests {
    private func story(_ title: String) -> FeedStory {
        FeedStory(guid: title, feedID: UUID(), title: title, link: nil, published: .now,
                  summary: nil, imageURL: nil)
    }

    @Test func subtitlesStandForTheGame() {
        let silksong = UUID()
        let m = GameNewsMatcher(games: [(silksong, "Hollow Knight: Silksong", "playing")])
        #expect(m.games(in: story("Silksong patch 1.0.3 rebalances Act 3")).map(\.gameID) == [silksong])
        #expect(m.games(in: story("Hollow Knight: Silksong sells 5 million")).count == 1)
    }

    @Test func theSeriesNameBeforeTheColonCounts() {
        let m = GameNewsMatcher(games: [(UUID(), "LEGO Batman: Legacy of the Dark Knight", "wishlist")])
        #expect(m.games(in: story("LEGO Batman arrives on Switch 2 today")).count == 1)
        let one = GameNewsMatcher(games: [(UUID(), "Control: Ultimate Edition", "playing")])
        #expect(one.games(in: story("Take control of your backlog")).isEmpty)
    }

    @Test func oneWordNamesNeedTheirCapital() {
        let m = GameNewsMatcher(games: [(UUID(), "Control", "playing")])
        #expect(m.games(in: story("Remedy confirms Control 2 for 2027")).count == 1)
        #expect(m.games(in: story("How to take control of your backlog")).isEmpty)
    }

    @Test func genericSubtitlesDontMatchEverything() {
        let m = GameNewsMatcher(games: [(UUID(), "Resident Evil 4: Remake", "wishlist")])
        #expect(m.games(in: story("Every remake announced this year")).isEmpty)
    }
}

struct NewsRiverTests {
    let ign = UUID(), gi = UUID()
    let now = Date(timeIntervalSince1970: 1_789_700_000)

    private func s(_ id: String, _ feed: UUID, minutesAgo: Double, image: Bool) -> FeedStory {
        FeedStory(guid: id, feedID: feed, title: id, link: nil,
                  published: now.addingTimeInterval(-minutesAgo * 60), summary: nil,
                  imageURL: image ? URL(string: "https://x/\(id).jpg") : nil)
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func nothingIsDroppedEvenWhenFolded() {
        let stories = (0..<8).map { s("ign\($0)", ign, minutesAgo: Double($0 * 5), image: true) }
            + [s("gi", gi, minutesAgo: 3, image: false)]
        let blocks = NewsRiver.blocks(stories, lastVisit: nil, now: now, calendar: utc)
        var seen = 0
        for b in blocks {
            switch b {
            case .big, .row: seen += 1
            case .pair: seen += 2
            case .burst(_, let list): seen += list.count
            default: break
            }
        }
        #expect(seen == 9)
    }

    @Test func aBurstKeepsTwoAndFoldsTheRest() {
        let stories = (0..<6).map { s("ign\($0)", ign, minutesAgo: Double($0 * 10), image: false) }
        let blocks = NewsRiver.blocks(stories, lastVisit: nil, now: now, calendar: utc)
        let bursts = blocks.compactMap { b -> [FeedStory]? in
            if case .burst(_, let list) = b { return list } else { return nil }
        }
        #expect(bursts.count == 1)
        #expect(bursts.first?.count == 4)
        // Expanded, it becomes rows where it sat.
        let id = blocks.first { if case .burst = $0 { true } else { false } }!.id
        let open = NewsRiver.blocks(stories, lastVisit: nil, expanded: [id], now: now, calendar: utc)
        #expect(!open.contains { if case .burst = $0 { true } else { false } })
    }

    @Test func caughtUpSitsBetweenNewAndSeen() throws {
        let stories = [s("new", gi, minutesAgo: 5, image: false),
                       s("old", ign, minutesAgo: 120, image: false)]
        let blocks = NewsRiver.blocks(stories, lastVisit: now.addingTimeInterval(-60 * 60), now: now, calendar: utc)
        let ids = blocks.map(\.id)
        let marker = try #require(ids.firstIndex(of: "caughtUp"))
        let newAt = try #require(ids.firstIndex(of: "row|\(stories[0].id)"))
        let oldAt = try #require(ids.firstIndex(of: "row|\(stories[1].id)"))
        #expect(newAt < marker && marker < oldAt)
    }

    @Test func noMarkerWhenEverythingIsOld() {
        let stories = [s("old", ign, minutesAgo: 120, image: false)]
        let blocks = NewsRiver.blocks(stories, lastVisit: now, now: now, calendar: utc)
        #expect(!blocks.contains(.caughtUp))
    }

    @Test func picturesPairUpAndTheDayLeadsBig() {
        let stories = (0..<3).map { s("p\($0)", $0 == 1 ? gi : ign, minutesAgo: Double($0 * 20), image: true) }
        let blocks = NewsRiver.blocks(stories, lastVisit: nil, now: now, calendar: utc)
        let shapes = blocks.compactMap { b -> String? in
            switch b {
            case .big: "big"
            case .pair: "pair"
            case .row: "row"
            default: nil
            }
        }
        #expect(shapes.first == "big")
        #expect(shapes.contains("pair"))
    }
}

@MainActor
struct NewsRepositoryTests {
    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @Test func startersSeedOnceAndNeverOverAChoice() throws {
        let r = repo()
        #expect(r.seedStarterFeedsIfNeeded())
        #expect(r.liveFeeds().count == 7)
        // Unfollowing a starter is a choice a second seed must not undo.
        r.unfollow(r.liveFeeds()[0])
        #expect(!r.seedStarterFeedsIfNeeded())
        #expect(r.liveFeeds().count == 6)
    }

    @Test func twoDevicesSeedingFoldIntoOne() {
        let r = repo()
        r.seedStarterFeedsIfNeeded()
        // The second device's copy arriving by sync.
        for entry in FeedCatalog.startsOn {
            r.context.insert(NewsFeed(urlString: entry.feedURL.replacingOccurrences(of: "https://www.", with: "http://"),
                                      title: entry.name))
        }
        r.dedupeFeeds()
        #expect(r.liveFeeds().count == 7)
    }

    @Test func followingAnOffFeedSwitchesItOn() {
        let r = repo()
        let f = r.follow(url: "https://www.purexbox.com/feeds/latest", title: "Pure Xbox", siteURL: nil)
        r.setFeed(f, on: false)
        #expect(f.muted)
        let again = r.follow(url: "http://purexbox.com/feeds/latest/", title: "Pure Xbox", siteURL: nil)
        #expect(again.id == f.id)
        #expect(!f.muted)
    }

    @Test func savingKeepsEnoughToShowItAndUnsavingCleansUp() throws {
        let r = repo()
        let story = FeedStory(guid: "g1", feedID: UUID(), title: "Silksong, 100 hours later",
                              link: URL(string: "https://eurogamer.net/a"), published: .now,
                              summary: nil, imageURL: nil)
        r.setSaved(story, true)
        let saved = try #require(r.storyStates().first)
        #expect(saved.saved && saved.title == story.title && saved.linkString == "https://eurogamer.net/a")
        r.setSaved(story, false)
        #expect(r.storyStates().isEmpty)
        // Read and then saved is one record, and unsaving keeps the read.
        r.markRead(story)
        r.setSaved(story, true)
        r.setSaved(story, false)
        #expect(r.storyStates().count == 1)
        #expect(r.storyStates().first?.read == true)
    }
}
