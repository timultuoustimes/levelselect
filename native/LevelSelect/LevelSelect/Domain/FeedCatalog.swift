import Foundation

/// The gaming feeds LevelSelect knows about, and the few that start on.
///
/// **Every address here was fetched on 2026-09-17** and was live, posting that
/// week, with images unless noted. The ones that failed that day are left out
/// rather than listed hopefully: Giant Bomb's site feed (403), GoNintendo
/// (404), TouchArcade (last post April 2025), PC Invasion (May 2025), Mac
/// Gamer HQ (September 2025), and the Epic Games Store, which has no public
/// feed. A feed that goes quiet later just shows nothing new; nothing breaks.
///
/// **Seven start on** — two general sites, one per platform, and retro — so
/// a first launch has a full front page without anyone choosing anything. Tim
/// on 09-17: *"start the app loaded with a handful of gaming related RSS feeds
/// that they can turn on and off or add to."*
///
/// **There is no Mac group**, because there is no live Mac gaming site with a
/// feed. Mac is a topic instead (`NewsTopic.mac`), matched across every feed.
enum FeedCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        let name: String
        let feedURL: String
        let siteURL: String
        let group: Group
        let blurb: String
        var startsOn = false
        var id: String { feedURL }
    }

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case everything = "Everything"
        case nintendo = "Nintendo"
        case playstation = "PlayStation"
        case xbox = "Xbox"
        case pc = "PC & Steam"
        case retro = "Retro"
        case rpg = "RPG & Japan"
        case mobile = "Mobile"
        case culture = "Industry & Culture"
        var id: String { rawValue }

        /// The topic whose owners should see this group first.
        var topic: NewsTopic? {
            switch self {
            case .nintendo: .nintendo
            case .playstation: .playstation
            case .xbox: .xbox
            case .pc: .pc
            case .retro: .retro
            default: nil
            }
        }
    }

    static let all: [Entry] = [
        // Everything
        .init(name: "Game Informer", feedURL: "https://www.gameinformer.com/rss.xml",
              siteURL: "https://www.gameinformer.com", group: .everything,
              blurb: "News, reviews and features", startsOn: true),
        .init(name: "IGN", feedURL: "https://feeds.ign.com/ign/games-all",
              siteURL: "https://www.ign.com", group: .everything,
              blurb: "Busy — news all day", startsOn: true),
        .init(name: "Eurogamer", feedURL: "https://www.eurogamer.net/feed",
              siteURL: "https://www.eurogamer.net", group: .everything, blurb: "News, reviews, Digital Foundry"),
        .init(name: "GamesRadar+", feedURL: "https://www.gamesradar.com/rss/",
              siteURL: "https://www.gamesradar.com", group: .everything, blurb: "News and guides"),
        .init(name: "Polygon", feedURL: "https://www.polygon.com/rss/index.xml",
              siteURL: "https://www.polygon.com", group: .everything, blurb: "News, reviews and culture"),
        .init(name: "Kotaku", feedURL: "https://kotaku.com/rss",
              siteURL: "https://kotaku.com", group: .everything, blurb: "News and opinion"),
        .init(name: "Destructoid", feedURL: "https://www.destructoid.com/feed/",
              siteURL: "https://www.destructoid.com", group: .everything, blurb: "News and reviews"),
        .init(name: "VGC", feedURL: "https://www.videogameschronicle.com/feed/",
              siteURL: "https://www.videogameschronicle.com", group: .everything, blurb: "Video Games Chronicle"),
        .init(name: "TheGamer", feedURL: "https://www.thegamer.com/feed/",
              siteURL: "https://www.thegamer.com", group: .everything, blurb: "News and guides"),
        .init(name: "Shacknews", feedURL: "https://www.shacknews.com/feed/rss",
              siteURL: "https://www.shacknews.com", group: .everything, blurb: "News and reviews"),
        .init(name: "The Verge — Games", feedURL: "https://www.theverge.com/rss/games/index.xml",
              siteURL: "https://www.theverge.com/games", group: .everything, blurb: "Games coverage"),
        .init(name: "Hardcore Gamer", feedURL: "https://hardcoregamer.com/feed/",
              siteURL: "https://hardcoregamer.com", group: .everything, blurb: "News and reviews"),

        // Nintendo
        .init(name: "Nintendo Life", feedURL: "https://www.nintendolife.com/feeds/latest",
              siteURL: "https://www.nintendolife.com", group: .nintendo,
              blurb: "Daily news and reviews", startsOn: true),
        .init(name: "Nintendo Everything", feedURL: "https://nintendoeverything.com/feed/",
              siteURL: "https://nintendoeverything.com", group: .nintendo, blurb: "Updates, patches, Japan news"),
        .init(name: "My Nintendo News", feedURL: "https://mynintendonews.com/feed/",
              siteURL: "https://mynintendonews.com", group: .nintendo, blurb: "Quick news · no images"),

        // PlayStation
        .init(name: "Push Square", feedURL: "https://www.pushsquare.com/feeds/latest",
              siteURL: "https://www.pushsquare.com", group: .playstation,
              blurb: "Daily news and reviews", startsOn: true),
        .init(name: "PlayStation Blog", feedURL: "https://blog.playstation.com/feed/",
              siteURL: "https://blog.playstation.com", group: .playstation, blurb: "Official · announcements"),

        // Xbox
        .init(name: "Pure Xbox", feedURL: "https://www.purexbox.com/feeds/latest",
              siteURL: "https://www.purexbox.com", group: .xbox,
              blurb: "Daily news and reviews", startsOn: true),
        .init(name: "Xbox Wire", feedURL: "https://news.xbox.com/en-us/feed/",
              siteURL: "https://news.xbox.com", group: .xbox, blurb: "Official · announcements"),

        // PC & Steam
        .init(name: "PC Gamer", feedURL: "https://www.pcgamer.com/rss/",
              siteURL: "https://www.pcgamer.com", group: .pc,
              blurb: "Busy — news, reviews, hardware", startsOn: true),
        .init(name: "Rock Paper Shotgun", feedURL: "https://www.rockpapershotgun.com/feed",
              siteURL: "https://www.rockpapershotgun.com", group: .pc, blurb: "PC news and opinion"),
        .init(name: "PCGamesN", feedURL: "https://www.pcgamesn.com/mainrss.xml",
              siteURL: "https://www.pcgamesn.com", group: .pc, blurb: "PC and Steam news"),
        .init(name: "GamingOnLinux", feedURL: "https://www.gamingonlinux.com/article_rss.php",
              siteURL: "https://www.gamingonlinux.com", group: .pc, blurb: "Linux, Proton, Steam Deck"),
        .init(name: "Steam Deck HQ", feedURL: "https://steamdeckhq.com/feed/",
              siteURL: "https://steamdeckhq.com", group: .pc, blurb: "Steam Deck news and settings"),
        .init(name: "Digital Foundry", feedURL: "https://www.digitalfoundry.net/feed",
              siteURL: "https://www.digitalfoundry.net", group: .pc, blurb: "Performance and tech, Mac ports too"),
        .init(name: "Wccftech — Games", feedURL: "https://wccftech.com/topic/games/feed/",
              siteURL: "https://wccftech.com", group: .pc, blurb: "Games, leaks and hardware"),
        .init(name: "Steam News", feedURL: "https://store.steampowered.com/feeds/news/",
              siteURL: "https://store.steampowered.com/news", group: .pc, blurb: "Official · Valve"),
        .init(name: "GOG News", feedURL: "https://www.gog.com/news/feed",
              siteURL: "https://www.gog.com/news", group: .pc, blurb: "Official · releases and sales, no images"),
        .init(name: "itch.io Featured", feedURL: "https://itch.io/feed/featured.xml",
              siteURL: "https://itch.io", group: .pc, blurb: "New indie games, not news"),

        // Retro
        .init(name: "Time Extension", feedURL: "https://www.timeextension.com/feeds/latest",
              siteURL: "https://www.timeextension.com", group: .retro,
              blurb: "Retro news and features", startsOn: true),
        .init(name: "Retro Dodo", feedURL: "https://retrododo.com/feed/",
              siteURL: "https://retrododo.com", group: .retro, blurb: "Retro handhelds and hardware"),
        .init(name: "RetroRGB", feedURL: "https://www.retrorgb.com/feed",
              siteURL: "https://www.retrorgb.com", group: .retro, blurb: "Retro video and mods"),
        .init(name: "Hardcore Gaming 101", feedURL: "http://www.hardcoregaming101.net/feed/",
              siteURL: "http://www.hardcoregaming101.net", group: .retro, blurb: "Long retrospectives · no images"),
        .init(name: "SEGADriven", feedURL: "https://www.segadriven.com/rss",
              siteURL: "https://www.segadriven.com", group: .retro, blurb: "SEGA news"),

        // RPG & Japan
        .init(name: "Gematsu", feedURL: "https://www.gematsu.com/feed",
              siteURL: "https://www.gematsu.com", group: .rpg, blurb: "Japanese releases, first"),
        .init(name: "Siliconera", feedURL: "https://www.siliconera.com/feed/",
              siteURL: "https://www.siliconera.com", group: .rpg, blurb: "Japanese and niche games"),
        .init(name: "RPG Site", feedURL: "https://www.rpgsite.net/feed",
              siteURL: "https://www.rpgsite.net", group: .rpg, blurb: "RPG news and reviews"),

        // Mobile
        .init(name: "Pocket Tactics", feedURL: "https://www.pockettactics.com/mainrss.xml",
              siteURL: "https://www.pockettactics.com", group: .mobile, blurb: "Mobile and handheld"),

        // Industry & culture
        .init(name: "Aftermath", feedURL: "https://aftermath.site/rss/",
              siteURL: "https://aftermath.site", group: .culture, blurb: "Worker-owned news and culture"),
        .init(name: "Game Developer", feedURL: "https://www.gamedeveloper.com/rss.xml",
              siteURL: "https://www.gamedeveloper.com", group: .culture, blurb: "The industry"),
        .init(name: "Unwinnable", feedURL: "https://unwinnable.com/feed/",
              siteURL: "https://unwinnable.com", group: .culture, blurb: "Criticism · no images"),
    ]

    static var startsOn: [Entry] { all.filter(\.startsOn) }

    static func entry(forFeedURL url: String) -> Entry? {
        let key = FeedDiscovery.key(url)
        return all.first { FeedDiscovery.key($0.feedURL) == key }
    }
}
