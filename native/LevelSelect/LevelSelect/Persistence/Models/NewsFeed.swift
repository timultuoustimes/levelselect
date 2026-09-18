import Foundation
import SwiftData

/// A feed you follow — a site's RSS or Atom, nothing more.
///
/// **Schema V7, 2026-09-17.** Tim chose the news reader for build 39 along
/// with three other schema items, taking the build wide before 1.0: *"I'm
/// good with taking my time and trying to get a lot out before build 40/1.0
/// release."*
///
/// What a feed is here is deliberately small: a URL, what to call it, and
/// where it sits. No article bodies, no images, no cached copies of anyone's
/// writing — the reader fetches, shows titles and summaries, and sends you to
/// the site. Storing articles would be republishing them.
@Model
final class NewsFeed {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// The feed itself.
    var urlString: String = ""
    /// What it calls itself, or what you renamed it to.
    var title: String = ""
    /// The site behind the feed, for "open in browser".
    var siteURLString: String?
    /// Your own grouping — "Nintendo", "Reviews", "Speedrunning".
    var folder: String?
    /// Your order within its folder.
    var sortIndex: Int = 0
    /// Followed but quiet: it still updates, and nothing about it is counted
    /// as unread.
    var muted: Bool = false
    /// When the app last read it, so a refresh can be polite.
    var lastFetchedAt: Date?
    /// The newest item seen, for ordering feeds by life.
    var lastItemAt: Date?

    init(id: UUID = UUID(), urlString: String = "", title: String = "") {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.urlString = urlString
        self.title = title
    }
}

/// What you've done with one article: read it, or kept it.
///
/// **Only articles you've touched are stored.** A feed of 5,000 items where
/// you read four is four records, not five thousand — the list you see is
/// fetched and held in memory, and this is the small permanent part that has
/// to survive a reinstall and reach your other devices.
@Model
final class NewsItemState {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// The feed it came from, by id rather than by relationship: a saved
    /// article outlives unfollowing the feed.
    var feedID: UUID?
    /// The feed's own id for the item (`guid`, or the link when there is none).
    var guid: String = ""
    /// Enough to show a saved item without re-fetching the feed.
    var title: String?
    var linkString: String?
    var publishedAt: Date?
    var read: Bool = false
    var saved: Bool = false

    init(id: UUID = UUID(), guid: String = "") {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.guid = guid
    }
}
